# vaultkeeping

Tooling y reglas del `dataMx-vault`. Repo hermano de la bóveda, **público y de
solo lectura para el equipo**: escritura solo el admin del vault. La razón es
de diseño — estos scripts son los candados de la bóveda, y un candado que puede
editar cualquiera (o cualquier agente de IA con acceso de escritura) no es un
candado.

**Regla dura por ser público: aquí nunca van datos de clientes ni contenido de
la bóveda** — solo tooling y reglas genéricas. La bóveda misma vive en su
propio repo privado.

**Ruta de clone fija: `~/repos/vaultkeeping`.** No es opcional: la config del
vault (`.claude/settings.json`, `AGENTS.md`) apunta a rutas absolutas dentro de
esta carpeta. Se clona una vez y no se toca.

Solo necesitas este repo si trabajas sobre la bóveda con terminal o con un
agente de IA. Si solo usas Obsidian, no te hace falta.

## Qué hay aquí

- `automation/` — los scripts:
  - `vaultChecker.sh` — audita el grafo de referencias (enlaces rotos, notas
    huérfanas)
  - `vaultGuard.sh` — vaultChecker + guard de borrado masivo; con `--install`
    se instala como pre-push hook en el clone de la bóveda
  - `commandGuard.sh` — hook PreToolUse de Claude Code que bloquea comandos
    destructivos (lo engancha solo el `.claude/settings.json` de la bóveda si
    este repo está clonado)
  - `newAccount.sh "Nombre"` — crea una cuenta nueva (knowledge + meetings +
    reportes) ya enlazada en el grafo
  - `rebuildGraphColors.sh` — reconstruye la paleta del Graph view de Obsidian
  - `backupVault.sh` — snapshot del repo de la bóveda a git bundles con fecha
    (rotación automática); la red de recuperación contra force-push o desastre
    local. Pensado para cron en la máquina del admin
- `agent-Guidelines/` — contexto y reglas para agentes de IA (`vault-context.md`,
  `read-write-zones.md`); el `AGENTS.md` de la bóveda apunta aquí
- `github-actions-security.md` — diseño de la capa de seguridad server-side
  (referencia; hoy no está activa)

## Setup en una máquina nueva (con terminal/agente)

```
git clone <url-de-este-repo> ~/repos/vaultkeeping
~/repos/vaultkeeping/automation/vaultGuard.sh --install ~/dataMx-vault
```

El segundo comando instala el pre-push hook en tu clone de la bóveda: cada push
corre primero el chequeo de grafo y el guard de borrado masivo.

## Solo admin

- Respaldo automático de la bóveda (cron cada hora):
  ```
  0 * * * * $HOME/repos/vaultkeeping/automation/backupVault.sh >/dev/null 2>&1
  ```
  Restaurar: `git clone ~/dataMx-vault-backups/vault-<fecha>.bundle carpeta`.
- Al crear este repo en GitHub (público), proteger `main`: Settings → Branches
  → block force pushes + restrict deletions — gratis en repos públicos.
