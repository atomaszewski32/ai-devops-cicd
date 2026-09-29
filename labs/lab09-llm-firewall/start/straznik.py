#!/usr/bin/env python3
"""Strażnik promptów — sprawdza treść, zanim trafi do modelu.

    python straznik.py "treść promptu"
    cat prompt.txt | python straznik.py
    python straznik.py --pelny "treść"     # dokłada skaner wykrywający prompt injection

Kod wyjścia 0 = przepuszczone, 1 = odrzucone. Dzięki temu wpina się jako krok w pipeline.

Tryb domyślny używa wyłącznie skanerów regułowych — działają natychmiast i nie pobierają
modeli. Tryb `--pelny` dokłada `PromptInjection`, który pobiera model z Hugging Face
(kilkaset MB przy pierwszym uruchomieniu). Na szkoleniu uruchom go raz przed blokiem,
żeby model był już w cache.
"""

import argparse
import sys

# Wzorce sekretów, które chcemy zatrzymać zanim opuszczą organizację.
# Lista jest krótka celowo — pełna lista i tak nie istnieje, o czym mówimy w demo.
WZORCE = [
    (r"AKIA[0-9A-Z]{16}", "klucz dostępowy AWS"),
    (r"(?i)aws_secret_access_key\s*[=:]\s*\S{20,}", "sekret AWS"),
    (r"gh[pousr]_[A-Za-z0-9]{36,}", "token GitHuba"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "klucz prywatny"),
    (r"(?i)(postgres(ql)?|mysql|mongodb)://[^\s:]+:[^\s@]+@", "connection string z hasłem"),
    (r"(?i)\b(hasło|password|passwd)\s*[=:]\s*\S{6,}", "hasło w treści"),
    (r"arn:aws[a-zA-Z0-9-]*:[a-zA-Z0-9-]*:[a-z0-9-]*:\d{12}:[^\s\"']+", "ARN AWS"),
    (r"\b\d{12}\b", "identyfikator konta AWS"),
]


def zbuduj_skanery(pelny: bool):
    from llm_guard.input_scanners import Regex, Secrets
    from llm_guard.input_scanners.regex import MatchType

    skanery = [
        Secrets(redact_mode="all"),
        Regex(
            patterns=[wzorzec for wzorzec, _ in WZORCE],
            is_blocked=True,
            match_type=MatchType.SEARCH,
        ),
    ]

    if pelny:
        from llm_guard.input_scanners import PromptInjection

        skanery.append(PromptInjection(threshold=0.85))

    return skanery


def main() -> int:
    parser = argparse.ArgumentParser(description="Strażnik promptów")
    parser.add_argument("prompt", nargs="?", help="treść promptu; bez tego czyta ze stdin")
    parser.add_argument("--pelny", action="store_true", help="dołącz skaner prompt injection")
    args = parser.parse_args()

    prompt = args.prompt if args.prompt else sys.stdin.read()
    if not prompt.strip():
        print("Pusty prompt — nie ma czego sprawdzać.", file=sys.stderr)
        return 1

    from llm_guard import scan_prompt

    skanery = zbuduj_skanery(args.pelny)
    _, wyniki, ryzyko = scan_prompt(skanery, prompt)

    odrzucone = [nazwa for nazwa, ok in wyniki.items() if not ok]

    if odrzucone:
        # Logujemy, KTÓRY skaner zareagował — nigdy samej treści, bo to właśnie ona
        # zawiera sekret, który próbujemy zatrzymać.
        print("ODRZUCONE. Zareagowały skanery: " + ", ".join(odrzucone), file=sys.stderr)
        print(f"Poziom ryzyka: {ryzyko}", file=sys.stderr)
        print("Treść promptu nie została zalogowana — to ona jest problemem.", file=sys.stderr)
        return 1

    print("Przepuszczone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
