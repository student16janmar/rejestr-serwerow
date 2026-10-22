# Rejestr serwerów i usług IT — projekt Student16

![CI](https://github.com/UZYTKOWNIK/rejestr-serwerow/actions/workflows/ci.yml/badge.svg)

Aplikacja do ewidencjonowania serwerów i usług działających w infrastrukturze IT.
Projekt końcowy z przedmiotu DevOps — kontenery w systemie Linux.

![Zrzut ekranu](docs/screenshot.png)

## Funkcjonalności

| Wymaganie | Realizacja |
|---|---|
| dodawanie serwerów z nazwą i adresem IP | formularz „+ Dodaj serwer” oraz `POST /api/servers`; IP walidowany (IPv4/IPv6), nazwa i IP unikalne |
| system operacyjny i opis roli serwera | pola `os`, `role` oraz `environment` (production / staging / development / test) |
| ewidencja usług (GitLab, Nginx, MySQL…) | usługi przypisane do serwera, z opcjonalnym portem |
| oznaczanie usług jako działających / niedostępnych | ręcznie (przyciski „działa” / „niedostępna”, `PATCH /api/services/<id>`) **oraz automatycznie** — kontener `checker` co 30 s sprawdza połączenie TCP z `IP:port` |
| filtrowanie i przeglądanie zasobów | wyszukiwanie po nazwie, IP, roli i nazwie usługi; filtry: stan serwera, środowisko, system, stan usług; sortowanie |

Stan serwera jest wyliczany z jego usług: **online** (wszystkie działają), **ostrzeżenie** (część niedostępna), **offline** (żadna nie działa), **nieznany** (brak sprawdzeń).

## Architektura

```
                  ┌────────── sieć frontend ──────────┐   ┌──────────── sieć backend ─────────────┐
 przeglądarka ──► │ nginx :10161 ──► app (Gunicorn)   │ ◄─┤ app ──► db (PostgreSQL 16) ◄── adminer │
                  │                  :10163           │   │          ▲  wolumen db-data   :10162  │
                  └───────────────────────────────────┘   │ checker ─┘  (port 10164)              │
                                                          └───────────────────────────────────────┘
```

| Kontener | Obraz | Rola | Port na PC16 |
|---|---|---|---|
| `nginx` | nginx:1.27-alpine | reverse proxy, główne wejście | **10161** |
| `adminer` | adminer:4 | podgląd bazy danych przez WWW | **10162** |
| `app` | własny (Dockerfile) | aplikacja Flask + Gunicorn, REST API | **10163** |
| `db` | postgres:16-alpine | baza danych, trwały wolumen `db-data` | **10164** |
| `checker` | własny (ten sam obraz) | cykliczne sprawdzanie dostępności usług | — |

* **Sieci Docker:** `frontend` (nginx ↔ app) i `backend` (app, checker, adminer ↔ db). Nginx nie ma dostępu do bazy.
* **Trwałe dane:** nazwany wolumen `db-data` → `/var/lib/postgresql/data`. Dane przetrwają `docker compose down` i restart.
* **Healthchecki:** `db` (`pg_isready`), `app` (`/health` sprawdza też połączenie z bazą). `app` startuje dopiero po zdrowej bazie, a `nginx` i `checker` po zdrowej aplikacji.
* **Dockerfile:** wieloetapowy (builder → runtime), `python:3.12-slim`, użytkownik bez uprawnień root, `HEALTHCHECK`.

## Uruchomienie na PC16 (172.31.115.16)

Dostęp do maszyny przez Apache Guacamole → terminal.

```bash
git clone https://github.com/UZYTKOWNIK/rejestr-serwerow.git
cd rejestr-serwerow
cp .env.example .env          # opcjonalnie zmień hasła
docker compose up -d --build
docker compose ps             # wszystkie kontenery powinny mieć stan running / healthy
```

Adresy:

* aplikacja: http://172.31.115.16:10161
* aplikacja bez proxy / API: http://172.31.115.16:10163/api/servers
* Adminer: http://172.31.115.16:10162 — system *PostgreSQL*, serwer `db`, użytkownik/hasło/baza z `.env`
* PostgreSQL: `172.31.115.16:10164`

Przy pierwszym starcie wczytywane są dane przykładowe (`SEED_DEMO=1`): serwer **PC16** z czterema usługami tego projektu (porty 10161–10164, sprawdzane automatycznie) oraz kilka serwerów przykładowych (GitLab, MySQL, kopie zapasowe), których stan ustawiono ręcznie.

Zatrzymanie: `docker compose down` (dane zostają) · pełne usunięcie z danymi: `docker compose down -v`.

## Testowanie

### Testy automatyczne (lokalnie)

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
ruff check .
pytest -v
```

9 testów: health, walidacja IP/portu/statusu, unikalność, wyliczanie stanu serwera, filtrowanie, formularze HTML, checker TCP (prawdziwe gniazdo otwarte i zamknięte).

### Test ręczny na PC16

```bash
# dodanie serwera i usługi przez API
curl -X POST http://localhost:10161/api/servers -H 'Content-Type: application/json' \
     -d '{"name":"gitlab-02","ip_address":"10.0.1.11","os":"Debian 12","role":"GitLab"}'
# 6 = "id" z odpowiedzi poprzedniego polecenia
curl -X POST http://localhost:10161/api/servers/6/services -H 'Content-Type: application/json' \
     -d '{"name":"GitLab","port":443,"status":"up","auto_check":false}'

# filtrowanie
curl "http://localhost:10161/api/servers?q=gitlab"
curl "http://localhost:10161/api/servers?status=warning"

# test trwałości danych
docker compose down && docker compose up -d
curl "http://localhost:10161/api/servers?q=gitlab-02"     # wpis nadal istnieje

# test automatycznego sprawdzania
docker compose stop adminer
sleep 35 && curl "http://localhost:10161/api/servers?q=PC16"  # Adminer -> "down"
docker compose start adminer
```

## CI/CD — GitHub Actions

Plik `.github/workflows/ci.yml`, uruchamiany przy każdym `push` i `pull request`.

1. **Kontrola projektu** — `ruff` (lint), `pytest`, `hadolint` (lint Dockerfile), `docker compose config` (walidacja compose).
2. **Budowanie obrazu i test stosu** — budowa obrazu (z cache), `docker compose up --wait`, test dymny przez `curl` (strona, health, API, Adminer), test trwałości danych po restarcie.
3. **Publikacja** — przy `push` na `main` obraz trafia do GitHub Container Registry: `ghcr.io/<użytkownik>/rejestr-serwerow:latest` oraz tag z SHA commita.

## REST API

| Metoda | Ścieżka | Opis |
|---|---|---|
| GET | `/health` | stan aplikacji i bazy |
| GET | `/api/stats` | liczniki serwerów i usług |
| GET | `/api/servers` | lista; parametry `q`, `status`, `environment`, `os`, `service_status`, `sort` |
| POST | `/api/servers` | nowy serwer `{name, ip_address, os, role, environment}` |
| GET / PUT / DELETE | `/api/servers/<id>` | odczyt / edycja / usunięcie |
| POST | `/api/servers/<id>/services` | nowa usługa `{name, port, status, auto_check}` |
| GET | `/api/services` | lista usług; `status`, `name` |
| PATCH | `/api/services/<id>` | zmiana `status` (`up`/`down`/`unknown`) lub `auto_check` |
| DELETE | `/api/services/<id>` | usunięcie usługi |

## Struktura repozytorium

```
├── app/                    aplikacja Flask
│   ├── __init__.py         fabryka aplikacji, /health, polecenie init-db, dane przykładowe
│   ├── models.py           modele Server i Service
│   ├── routes.py           widoki HTML i REST API, filtrowanie
│   ├── validation.py       walidacja danych
│   ├── checker.py          proces sprawdzający dostępność usług
│   ├── templates/          szablon interfejsu
│   └── static/             style CSS
├── nginx/default.conf      konfiguracja reverse proxy
├── tests/                  testy pytest
├── .github/workflows/      pipeline CI/CD
├── Dockerfile
├── docker-entrypoint.sh
├── compose.yaml
└── .env.example
```

## Udostępnienie prowadzącej

Repozytorium prywatne: *Settings → Collaborators → Add people* → `pyzik.lucyna@gmail.com`.
Repozytorium publiczne: wystarczy przesłać link.
