# Contexto para agentes de IA — dataMx-vault

Si estás leyendo esto, vas a trabajar dentro de `dataMx-vault`, la bóveda de
Obsidian de una agencia de social media. Guarda insights y bitácoras del "always
on" y campañas, organizado por marca/cuenta, para que el equipo no repita
aprendizajes ya hechos.

Antes de tocar nada, lee también `read-write-zones.md` en esta misma carpeta —
ahí están las zonas de solo lectura.

## Estructura, carpeta por carpeta

| Carpeta | Para qué es |
|---|---|
| `inbox/` | Todo lo sin clasificar aterriza aquí primero |
| `daybook/` | Notas del día a día |
| `activeProjects/` | Proyectos en curso, con dueño y fecha |
| `decisions/` | Temas abiertos que el equipo tiene que resolver — `Decisions Board.md` es el Kanban, `threads/` es donde se discute cada tarjeta |
| `knowledge/brands/<Slug>/` | Lo que el equipo aprendió de cada cuenta, en sus propias palabras |
| `meetings/client/<Slug>/` | Bitácoras de llamadas/juntas por cuenta |
| `onBoarding/` | Cómo arranca alguien nuevo en el vault |
| `templates/` | Los moldes desde donde se copian notas nuevas (cuentas, etc.) |
| `index/` | Mapa de mapas — apunta a los índices del resto del vault |
| `toLearn/` | Leído, no procesado todavía |
| `archive/` | Trabajo terminado, se guarda de referencia, no se reabre |
| `trash/` | Etapa previa a borrar algo — no es borrado real |

## Convenciones ya establecidas (no las rompas sin que te lo pidan)

- **Un nombre de archivo único por nota en todo el vault.** No hay `README.md`
  genérico repetido por carpeta — cada nota se llama como su propio H1
  (`Active Projects.md`, `Knowledge.md`, etc.). Esto es a propósito: la vista de
  Graph de Obsidian rotula los nodos por nombre de archivo, y nombres repetidos la
  vuelven ilegible. La única excepción es el `README.md` de la raíz.
- **Todos los enlaces internos son wikilinks** (`[[ruta/completa|alias]]`), no
  markdown links (`[texto](ruta)`). Los wikilinks se autoactualizan cuando Obsidian
  renombra o mueve una nota; los markdown links no.
- **Cuentas nuevas se crean con el script, no a mano:**
  `~/repos/vaultkeeping/automation/newAccount.sh "Nombre de la Marca"` — arma
  `knowledge/brands/<Slug>/<Marca> Knowledge.md` y
  `meetings/client/<Slug>/<Marca> Meetings.md`, los cruza entre sí, y los agrega a
  `Brands.md`/`Clientes.md`. Crear estas carpetas/archivos a mano es exactamente
  como se rompió el grafo la primera vez.
- **Después de cualquier cambio estructural** (mover, renombrar, borrar notas, o
  tocar un índice), corre `~/repos/vaultkeeping/automation/vaultChecker.sh ~/dataMx-vault` y
  confirma "Broken links: none" / "Orphan notes: none" antes de darlo por
  terminado.

## Cosecha de conocimiento (cómo se sintetiza)

El vault registra en capas operativas y acumula en capas de conocimiento. La
regla de dirección: **nada en Knowledge enlaza hacia abajo** (tarjetas de
Kanban, bitácoras sueltas, tmp) — lo aprendido se empuja hacia arriba.

- **Fuentes:** bitácoras de reunión (`### Notas`), reportes (`### Insights` de
  cada report-link), threads de decisión resueltos.
- **Destino:** la sección `## Insights` del Knowledge de la marca — o
  `knowledge/Transversal.md` si aplica a más de una cuenta.
- **Formato de cada insight:** `- **YYYY-MM-DD** — <lo aprendido> #<tag-autor>`
  (el mismo que produce el botón 🧠 Nuevo insight).
- Si te piden un rollup ("resume lo aprendido de X este mes"), lee las fuentes,
  escribe al destino en ese formato con la fecha de hoy y el tag de quien te lo
  pidió, y **no borres ni edites las fuentes** — la síntesis suma, no reemplaza.
