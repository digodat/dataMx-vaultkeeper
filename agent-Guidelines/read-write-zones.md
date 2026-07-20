# Zonas de lectura/escritura — dataMx-vault

Esto es la **tercera capa** de seguridad sobre la bóveda, y es la única de las tres
que es una petición, no un candado:

1. Guard de git (`automation/vaultGuard.sh` como pre-push hook, más la protección
   que dé el hosting del remoto) — técnico, agnóstico de herramienta.
2. `.claude/settings.json` + `commandGuard.sh` — técnico, solo para Claude Code.
3. **Este documento** — contexto y reglas para que cualquier agente (sin importar
   la herramienta) sepa qué se espera, pero depende de que lo lea y lo respete. Si
   lo ignora, las capas 1 y 2 son las que de verdad lo frenan.

No asumas que por estar aquí ya estás protegido — sigue aplicando lo mismo que en
cualquier repo: nada de `rm -rf`, `git push --force`/`-f`, `git reset --hard`,
`git clean -f`, `git branch -D`, `git filter-branch`, ni borrados masivos. Esas
quedan bloqueadas técnicamente de todas formas, pero no las intentes ni con buena
intención.

## Puede escribir libremente

| Zona | Por qué |
|---|---|
| `inbox/` | Es su propósito — todo lo sin clasificar aterriza aquí |
| `daybook/` | Notas del día a día |
| `activeProjects/` | Proyectos en curso |
| `toLearn/` | Cola de lectura |
| `decisions/threads/*.md` | Discusión de un tema ya abierto en el Kanban |
| `knowledge/brands/<Slug>/*.md` | Acumular aprendizajes de una cuenta ya creada |
| `knowledge/Transversal.md` | Insights que aplican a varias cuentas — agregar bullets bajo `## Insights`, mismo formato que el botón 🧠 |
| `meetings/client/<Slug>/*.md` | Nuevas bitácoras de una cuenta ya creada |

Para una **cuenta que no existe todavía**, no crear las carpetas a mano — correr
`~/repos/vaultkeeping/automation/newAccount.sh "Nombre"` (ver `vault-context.md`).

## Puede escribir, con cuidado

| Zona | Cuidado |
|---|---|
| `decisions/Decisions Board.md`, `onBoarding/Onboarding Kanban.md` | Son tableros Kanban compartidos — alto riesgo de conflicto si dos personas mueven tarjetas casi al mismo tiempo. Agregar, no reestructurar columnas. |
| Notas índice/agregadoras (`Brands.md`, `Clientes.md`, `Knowledge.md`, `Meetings.md`, root `README.md`, `index/Index.md`) | Agregar una entrada nueva está bien (así trabaja `newAccount.sh`). Reordenar o rediseñar la lista es una decisión de estructura, no una edición de contenido — preguntar primero. |

## Solo lectura — no modificar sin que Stephan lo pida explícitamente

| Zona | Por qué |
|---|---|
| `templates/*.md` | Cambiar el molde cambia el patrón de **todas** las cuentas futuras, no solo la actual |
| `archive/` | Trabajo terminado que se guarda de referencia — no se reabre |
| `trash/` | Etapa de borrado — moverlo o vaciarlo es una decisión humana, no una limpieza automática |
| `tmp/` | Carpeta de scratch de los formularios (Templater + Buttons + Modal forms) que usa el equipo desde Obsidian — gitignored, nunca sincroniza. Si un agente ve archivos ahí (a veces con sintaxis `<%* %>` sin procesar por una colisión de guardado), son desechables — no reflejan contenido real del vault, ignóralos |
| `.claude/settings.json` (dentro de la bóveda) | Es la config de permisos misma — un agente editando su propia config de seguridad es exactamente el escenario que esto existe para evitar |
| Todo `~/repos/vaultkeeping/` (fuera de la bóveda) | Son los scripts que hacen cumplir las capas 1 y 2 — igual que arriba, no se autoedita el candado |

## Si algo no encaja en esta lista

Trátalo como solo-lectura hasta preguntar. Es más barato pedir permiso una vez que
deshacer un cambio estructural que nadie pidió.
