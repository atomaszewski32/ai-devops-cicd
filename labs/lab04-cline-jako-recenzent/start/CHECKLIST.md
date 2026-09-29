# Checklista recenzenta — ai-devops-cicd

Do użycia bez AI, przy każdym PR w tym repo. Zaznacz tylko to, co dotyczy zmienionych
plików — nie każdy punkt pasuje do każdego PR. Dla każdego znalezionego problemu podaj
**plik:linię** i **konkretny scenariusz**, w którym to wybucha; uwaga bez scenariusza
to zgadywanie, nie recenzja.

## 1. Poprawność

- [ ] Kod robi to, co obiecuje opis PR — nic mniej, nic więcej
- [ ] Puste/brakujące wejście jest obsłużone jawnie (błąd albo sensowny default), nie ciche przejście dalej
- [ ] Brak uprawnień / błąd autoryzacji jest obsłużony, nie tylko „happy path”
- [ ] Timeouty na wywołaniach HTTP/zewnętrznych zależności są ustawione (nie ma nieskończonego czekania)
- [ ] Równoległe/powtórne wywołania nie prowadzą do race condition (np. workflow bez `concurrency:`, brak idempotencji)
- [ ] Kroki w CI faktycznie mogą się wykonać w kolejności, w jakiej są zapisane (np. czy przed `kubectl` jest krok logowania do klastra)

## 2. Bezpieczeństwo

- [ ] Żadnych sekretów jako wartości w kodzie/Dockerfile/workflow (`ENV KEY=...`, hasła, tokeny) — tylko GitHub Secrets
- [ ] `permissions:` w workflow jest zawężone do minimum na poziomie joba, nigdy `write-all` „na wszelki wypadek”
- [ ] Triggery typu `issue_comment` / `pull_request_target` mają weryfikację autora (`author_association` albo lista uprawnionych), nie tylko dopasowanie tekstu
- [ ] Wartości z wejścia użytkownika (komentarz, PR, issue) nie trafiają bezpośrednio do `run:` przez `${{ }}` — ryzyko wstrzyknięcia poleceń; jeśli muszą, to przez zmienną środowiskową (`env:`), nie interpolację w skrypcie
- [ ] Uwierzytelnianie do AWS przez OIDC, nie długożyjące klucze (`AWS_SECRET_ACCESS_KEY` w sekretach to czerwona flaga w tym repo)
- [ ] Dane użytkownika nie trafiają do logów (całe obiekty żądania, nagłówki, tokeny)
- [ ] Zapytania do bazy nie są składane przez konkatenację stringów
- [ ] Akcje/obrazy bazowe są pinowane do wersji lub SHA, nie do ruchomej gałęzi (`@main`, `latest`)
- [ ] Security group / dostęp sieciowy: żadnego `0.0.0.0/0` poza portem 443
- [ ] Kontener nie działa jako root bez powodu (`USER` w Dockerfile)
- [ ] Nikt nie dopisał `#checkov:skip` / `#tfsec:ignore` żeby uciszyć skaner zamiast naprawić przyczynę

## 3. Złożoność i wydajność

- [ ] Brak zapytań do bazy/API w pętli (N+1)
- [ ] Brak operacji O(n²) na danych, które w praktyce rosną
- [ ] Funkcja/krok robi jedną rzecz — jeśli robi dwie, czy da się je rozdzielić?
- [ ] Kolejność warstw w Dockerfile wspiera cache (zależności przed kodem źródłowym, nie `COPY . .` na starcie)
- [ ] Jest `.dockerignore` — build nie kopiuje całego katalogu roboczego bez potrzeby

## 4. Zgodność z konwencjami repo (`.claude/CLAUDE.md`)

- [ ] Wdrożenia na EKS przez Argo Rollouts (`Rollout`), nie `Deployment` — wyjątek: `app/k8s-dzien1/`
- [ ] Nazwy zasobów AWS: `szkolenie-<blok>-<zasob>-<uczestnik>`
- [ ] Każdy zasób AWS ma tagi: `Projekt`, `Uczestnik`, `Blok`, `Usuwac = tak`
- [ ] Zmienne Terraform mają `description` i jawny `type`
- [ ] Bucket S3: szyfrowanie, blokada publicznego dostępu, wersjonowanie włączone
- [ ] Workflow GitHub Actions ma `permissions:` na poziomie joba **i** `timeout-minutes`
- [ ] Nie podniesiono wersji providerów/actions „przy okazji” niezwiązanej zmiany
- [ ] `terraform apply` / `kubectl delete` nie zostały uruchomione bez wyraźnej prośby — PR proponuje `plan`, nie stosuje go sam
- [ ] Zmiana nie dotyka `.env`, `*.tfvars`, `credentials` (te pliki nie powinny w ogóle być w repo)
- [ ] Komentarze i teksty dla użytkownika po polsku, nazwy techniczne po angielsku

## Na koniec

- [ ] Znaleziska uszeregowane: BLOKUJĄCE / WAŻNE / drobne — recenzja z dwudziestoma
      równorzędnymi uwagami nie zostanie przeczytana do końca
- [ ] Werdykt jednoznaczny: `APROBATA` albo `DO POPRAWY` + lista tego, co blokuje
