# Asegurar la bóveda con GitHub Actions

Guía de referencia para cuando `dataMx-vault` tenga remoto en GitHub. No requiere que
tú apruebes cada cambio a mano — el objetivo es que la escritura se sienta "viva"
(push directo, sin fricción) pero que un desastre grande (alucinación de un agente,
borrado masivo, un push que rompe el grafo de referencias) se rechace solo, antes de
tocar la copia compartida.

Es un modelo de **sync + security**, tres capas que trabajan juntas:

1. **Sync** — el plugin **Obsidian Git** es el que mueve los cambios de verdad, en
   segundo plano, sin que nadie corra comandos de git a mano. Es lo que hace que se
   sienta "vivo".
2. **Quién puede empujar cambios** — roles de GitHub (Write vs Read), independiente
   del plugin.
3. **Qué cambios se aceptan** — GitHub Actions + branch protection, revisa lo que
   el plugin ya empujó y rechaza lo que rompe la bóveda.

Ninguna de las tres sola es suficiente: sin el plugin no hay sync; sin roles,
cualquiera puede empujar; sin el Action, un push válido (con permiso) puede seguir
siendo un desastre.

**Decisión de alcance:** el equipo va a usar varias herramientas de IA distintas
(Claude Code, Cursor, Codex, Gemini CLI, Antigravity...), cada una con su propio
formato de permisos/config, sin overlap entre ellas. En vez de mantener una
blacklist duplicada por herramienta (5 copias de la misma política, garantizado que
se desalinean), la protección real vive **aquí, a nivel git** — es agnóstica de
herramienta por construcción: no importa quién generó el comando, todo tiene que
pasar por `git push` para tocar la copia compartida. `.claude/settings.json` (ver
`vaultkeeping/automation/commandGuard.sh`) existe solo como capa extra para quien use Claude
Code específicamente — no es la línea de defensa que cubre a todo el equipo, esa es
esta.

---

## 1. Roles: quién tiene push

GitHub ya trae esto, no hace falta un plugin extra.

| Rol | Puede | Para quién |
|---|---|---|
| **Owner** (tú) | Todo: cambiar settings, borrar el repo, forzar sobre ramas protegidas | Tú, nadie más |
| **Write** (colaborador) | Clonar, hacer push a ramas no protegidas, abrir PRs | Gente de confianza que escribe seguido |
| **Read** / Deploy key de solo lectura | Clonar y leer, **no puede hacer push** | Cualquiera cuyo agente de IA solo necesite contexto de la bóveda |

- Settings → Collaborators → agregar por rol. Para un agente/proceso automatizado que
  solo necesita leer (no una persona), usa **Settings → Deploy keys** en vez de un
  colaborador — es una llave de solo lectura por defecto, atada al repo, no a una
  cuenta de GitHub.
- Nadie fuera de "Write" u "Owner" puede escribir en la bóveda compartida, sin
  importar qué haga su agente localmente. Lo que pase en su clon local se queda ahí.

---

## 2. El plugin Obsidian Git (la parte "sync")

Esto es lo que corre dentro de Obsidian, en la máquina de cada quien — es la pieza
que le da el efecto "vivo". Community plugins → instalar **Obsidian Git**. La
configuración cambia según el rol de la persona (sección 1):

**Para "Write" (tú y la gente de confianza):**
- `Auto pull interval`: ~10 min — trae lo último de `main` seguido, así se ve casi
  en tiempo real lo que escribió otro.
- `Auto backup interval` (auto-commit local): ~10 min.
- `Auto push on backup`: **activado** — cada auto-commit se empuja solo a `main`.
  Esto es lo que dispara el Action de la sección 4 en cada push.
- `Pull before push`: activado — evita conflictos tontos por estar un paso atrás.
- `Pull on Obsidian start`: activado — al abrir Obsidian, ya tienes lo último antes
  de escribir encima de algo viejo.

**Para "Read" (agentes o personas de solo lectura):**
- Solo `Auto pull` — sin auto-push. No hace falta ni desactivarlo a propósito: como
  su credencial de git es de solo lectura (sección 1), un intento de push fallaría
  igual — pero es más limpio apagarlo para que no les salga un error confuso cada
  rato.

**Qué se siente cuando el Action rechaza algo:** a quien le pasó, Obsidian Git le va
a mostrar una notificación de "push rejected" / falló el push. No es un bug — es la
capa de seguridad de la sección 4 funcionando. La persona corrige y vuelve a
guardar; nada roto llegó a tocar la copia compartida mientras tanto.

**Límite real:** Obsidian Git es git normal por debajo, no fusiona en tiempo real
como un Google Docs. Si dos personas editan la *misma línea* del mismo archivo
antes de que corra el próximo auto-pull, va a haber conflicto de merge. Los
archivos de Kanban (`Decisions Board`, `Onboarding Kanban`) son el punto más
probable de esto — vale la pena bajar su `Auto backup interval` a algo más corto
(2-3 min) si se va a editar seguido en paralelo.

---

## 3. Branch protection en `main`

Settings → Branches → Add branch protection rule → `main`:

- ✅ **Require status checks to pass before merging** — engancha el workflow de la
  sección 4. Esto es lo que bloquea automático, sin que tú tengas que mirar.
- ✅ **Require branches to be up to date before merging**
- ⬜ *Require a pull request before merging* — déjalo apagado si quieres que el
  "Write" tier pueda seguir empujando directo a `main` (efecto "vivo"). Actívalo
  solo si prefieres cambiar a modo revisión manual más adelante.
- ✅ **Do not allow bypassing the above settings** (aplica incluso a Owner, salvo que
  tú mismo decidas lo contrario caso por caso)

Con status checks + sin PR obligatorio: la gente de confianza sigue empujando
directo, pero cualquier push que reprueba el check queda rechazado por GitHub,
nadie tiene que aprobarlo a mano.

---

## 4. El workflow: `vaultChecker` como status check obligatorio

Importante: `vaultChecker.sh` vive fuera de la bóveda, en `~/repos/vaultkeeping/automation/`, a
propósito. GitHub Actions corre en una VM efímera de GitHub que solo ve lo que está
*dentro* del repo — no tiene acceso a tu carpeta `repos/` local. Por eso el chequeo
en CI necesita su propia copia de la lógica, versionada dentro del repo de la
bóveda, en `.github/workflows/`. Trátalo como una copia sincronizada a mano del
mismo chequeo, no como el script "real" (ese sigue siendo `vaultkeeping/automation/vaultChecker.sh`
para correr en tu máquina).

Crear en el repo de la bóveda: `.github/workflows/vault-integrity.yml`

```yaml
name: Vault Integrity

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  check-graph:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # necesita historia completa para comparar contra el commit anterior

      - name: Broken links / orphan notes
        run: |
          python3 - <<'PYEOF'
          # misma lógica que vaultkeeping/automation/vaultChecker.sh — mantenerlas en sync a mano
          import re, os, sys, urllib.parse

          md_files = []
          for root, dirs, files in os.walk('.'):
              dirs[:] = [d for d in dirs if d not in ('.git', '.obsidian')]
              for f in files:
                  if f.endswith('.md'):
                      md_files.append(os.path.normpath(os.path.join(root, f)))

          md_link_re = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
          wiki_link_re = re.compile(r'\[\[([^\]|]+)(\|[^\]]+)?\]\]')

          def in_code_fence(content, pos):
              return content[:pos].count('```') % 2 == 1

          broken = []
          incoming = {p: 0 for p in md_files}

          for p in sorted(md_files):
              is_template = p.startswith('templates' + os.sep)
              content = open(p, encoding='utf-8').read()
              base_dir = os.path.dirname(p)

              for m in md_link_re.finditer(content):
                  if in_code_fence(content, m.start()): continue
                  text, target = m.groups()
                  if target.startswith(('http://', 'https://', 'mailto:')): continue
                  t = urllib.parse.unquote(target.split('#')[0])
                  if not t: continue
                  resolved = os.path.normpath(os.path.join(base_dir, t))
                  if os.path.exists(resolved):
                      incoming[resolved] = incoming.get(resolved, 0) + 1
                  elif not is_template:
                      broken.append(f"[MD] {p} -> {target}")

              for m in wiki_link_re.finditer(content):
                  if in_code_fence(content, m.start()): continue
                  target = m.group(1).strip().split('#')[0]
                  if not target: continue
                  cand = target if target.endswith('.md') else target + '.md'
                  matches = [mp for mp in md_files if mp == cand or mp.endswith(os.sep + cand)]
                  if matches:
                      for mp in matches: incoming[mp] += 1
                  elif not is_template:
                      broken.append(f"[WIKI] {p} -> [[{target}]]")

          orphans = [p for p, c in incoming.items() if c == 0 and not p.startswith('templates' + os.sep)]

          if broken:
              print("Broken links:")
              for b in broken: print(" -", b)
          if orphans:
              print("Orphan notes:")
              for o in orphans: print(" -", o)

          sys.exit(1 if broken else 0)
          PYEOF

      - name: Guard against mass deletion
        run: |
          BASE="${{ github.event.pull_request.base.sha || github.event.before }}"
          if [ -z "$BASE" ] || [ "$BASE" = "0000000000000000000000000000000000000000" ]; then
            echo "No base commit to diff against (first push) — skipping."
            exit 0
          fi
          DELETED=$(git diff --name-status "$BASE" HEAD | awk '$1=="D"' | wc -l)
          echo "Files deleted in this push: $DELETED"
          if [ "$DELETED" -gt 5 ]; then
            echo "::error::Este push borra $DELETED archivos — se ve como borrado masivo. Bloqueado."
            exit 1
          fi
```

Ajusta el `5` del guard de borrado al tamaño real de la bóveda — la idea es que
tumbe un "borró 40 notas de un jalón", no que estorbe una limpieza normal de 2-3
archivos.

Con esto activado como *required status check* (sección 3), un push que rompe el
grafo o borra de golpe medio vault **no llega a `main`**, aunque venga de alguien
con permiso de escritura, del auto-push de su Obsidian Git, o de su agente de IA
corriendo con esas credenciales.

---

## 5. Capa extra opcional: mismo chequeo antes de salir de la máquina

Si además quieres frenar el problema *antes* de que salga a GitHub (no solo
rechazarlo del lado del servidor), un pre-push hook local en cada clon puede llamar
al `vaultChecker.sh` real:

`.git/hooks/pre-push` (por persona, no se versiona ni se comparte automático):

```bash
#!/usr/bin/env bash
~/repos/vaultkeeping/automation/vaultChecker.sh "$(git rev-parse --show-toplevel)" || {
  echo "vaultChecker encontró problemas — push cancelado."
  exit 1
}
```

Esto es best-effort (cada quien lo instala en su máquina, no es obligatorio como el
status check de GitHub), pero da feedback inmediato sin esperar a que corra la
Action.

---

## 6. Resumen de qué protege qué

| Amenaza | Qué la frena |
|---|---|
| Agente de IA de alguien sin permiso de escritura borra/cambia todo | Nunca tiene credenciales de push (sección 1) — se queda en su clon local |
| Auto-push del plugin manda un cambio a deshoras | Es solo sync, no valida nada — para eso está la sección 4 |
| Agente de IA de alguien **con** permiso de escritura rompe enlaces | Status check `vaultChecker` rechaza el push/PR |
| Borrado masivo accidental o alucinado | Guard de borrado masivo en el mismo workflow |
| "Se me olvidó y quedó roto igual, ya está en main" | No debería pasar — es *required*, GitHub no deja mergear/pushear si falla |
| Dos personas editan el mismo Kanban a la vez | Conflicto de merge normal de git — molesto, pero no pierde datos en silencio (sección 2) |
| Algo se te escapó de todas formas | Todo sigue siendo git: `git revert` / `git reset` a cualquier commit anterior |

Costo: GitHub Actions da minutos gratis de sobra para un repo privado de este
tamaño — no hay que preocuparse por billing para este uso.

---

## 7. Alternativa: que viva de tu lado, sin GitHub Actions

Si prefieres no depender de la nube para esto, `vaultkeeping/automation/vaultGuard.sh` hace lo
mismo que las secciones 4-5 pero corriendo local — mismo chequeo de grafo
(reusa `vaultChecker.sh`) + el mismo guard de borrado masivo, comparando contra el
commit que ya está en el remoto (lee los datos que git le manda a un pre-push hook).

```
vaultkeeping/automation/vaultGuard.sh --install [ruta-al-vault]   # instala el hook una vez
vaultkeeping/automation/vaultGuard.sh [ruta-al-vault]              # o correrlo a mano cuando quieras
```

Instalado como pre-push hook, un `git push` con un borrado masivo o un enlace roto
se rechaza ahí mismo, en la máquina, antes de que salga a ningún lado — probado con
un push normal (pasa) y uno que borra de golpe `knowledge/` y `meetings/` (lo
bloquea, `git push` regresa error y nada llega al remoto).

**Diferencia honesta con la sección 3-4:** esto es un hook *local*, cada quien lo
instala en su propio clon. Se puede saltar con `git push --no-verify` o borrando el
hook — no es una garantía del lado del servidor como el *required status check* de
GitHub. Trátalo como la primera línea de defensa (rápida, sin esperar a que corra
una Action) y las secciones 3-4 como la que de verdad no se puede evadir. Si no vas
a usar GitHub Actions en absoluto, `vaultGuard.sh` sigue siendo mucho mejor que nada
— solo ten claro que depende de que la gente no le pase `--no-verify` a propósito.
