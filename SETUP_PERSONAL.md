# Setup personal — Trabajando con el fork de frankea/Whisky

> Documentación personal de Fabian Lisantti (GitHub: **Rilpmcuni**).
> Fork creado el 5 jul 2026 desde `frankea/Whisky` (v3.5.0).

---

## 📋 Setup verificado (5 jul 2026)

| Componente | Versión |
|---|---|
| macOS | 26.5.2 (Tahoe) |
| Chip | Apple A18 Pro (arm64) |
| Xcode | 26.6 (Build 17F113) |
| Swift | 6.3.3 |
| Git | 2.50.1 (Apple Git-155) |
| Homebrew | 6.0.6 |
| GitHub CLI (`gh`) | 2.96.0 |
| SwiftFormat | 0.61.1 |
| SwiftLint | instalado vía brew |

---

## 🌐 Remotos configurados

```bash
git remote -v
# origin   https://github.com/Rilpmcuni/Whisky.git   (TU fork - pushes van acá)
# upstream https://github.com/frankea/Whisky.git     (proyecto original - pulls vienen de acá)
```

---

## 🔁 Sincronizar con el upstream (frankea/Whisky)

Cuando frankea publique cambios nuevos (commits, releases, fixes), traerlos a tu fork:

```bash
# 1. Asegurate de estar en main y limpio
git checkout main
git status

# 2. Bajar los últimos cambios de frankea
git fetch upstream

# 3. Merge (conservando tus commits si tenías alguno en main)
git merge upstream/main

# 4. Subir a tu fork en GitHub
git push origin main
```

**Alternativa más limpia (rebase)** — recomendada si vas a abrir PRs upstream:

```bash
git checkout main
git fetch upstream
git rebase upstream/main
git push origin main --force-with-lease
```

> ⚠️ `--force-with-lease` es más seguro que `-f` porque no sobreescribe si alguien más pusheó.

---

## 🛠️ Compilar localmente

### Build rápido del paquete lógico (WhiskyKit)
```bash
swift build --package-path WhiskyKit
```

### Tests del paquete lógico
```bash
swift test --package-path WhiskyKit
```

### Build de la app completa (sin firmado, igual que CI)
```bash
xcodebuild -project Whisky.xcodeproj \
  -scheme Whisky \
  -configuration Debug \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

### Abrir en Xcode (con GUI)
```bash
open Whisky.xcodeproj
```
Y después ▶️ Run (Cmd+R) desde Xcode.

### Schemes disponibles
- `Whisky` — app SwiftUI principal
- `WhiskyCmd` — tool CLI
- `WhiskyThumbnail` — extensión QuickLook

---

## 🎮 Correr la app y probar Steam + Epic

1. Abrí Xcode con `open Whisky.xcodeproj`
2. Seleccioná scheme **Whisky** → **My Mac**
3. ▶️ Run (Cmd+R)
4. En el primer arranque la app descarga ~313 MB del runtime Wine automáticamente:
   - Wine 11.0 (build Gcenx `11.0_1`)
   - DXVK 1.10.3
   - DXMT 0.80
   - D3DMetal (Apple GPTK)
   - MoltenVK
   - msync
5. Creás una **bottle** desde la UI
6. Dentro de la bottle instalás:
   - **Steam** (`steaminstall.exe`)
   - **Epic Games Launcher**
   - **EA App**, **Battle.net**, **Rockstar** (todos soportados de serie)
7. Iniciar sesión con tu cuenta y descargar juegos.

---

## 🌿 Flujo de trabajo para tus propias features

### Crear una rama para un cambio nuevo
```bash
# Estilo Frankea/CONTRIBUTING (prefijo: feature/, fix/, docs/, chore/, refactor/)
git checkout main
git checkout -b feature/mi-nueva-feature

# Hacés tus cambios...
swift format .           # formatear antes de commitear
swiftformat --lint .     # verificar estilo

# Commitear (referencia issues con whisky-app/whisky#NNNN si aplica)
git add .
git commit -m "feature: descripción clara del cambio"

# Subir a tu fork
git push origin feature/mi-nueva-feature
```

### Mantener tu rama actualizada mientras trabajás
```bash
# Traer últimos cambios de frankea a tu rama de feature
git fetch upstream
git rebase upstream/main
# Resolver conflictos si los hay...
git push origin feature/mi-nueva-feature --force-with-lease
```

### Abrir un PR a frankea/Whisky (si querés contribuir upstream)
```bash
gh pr create \
  --repo frankea/Whisky \
  --base main \
  --head Rilpmcuni:feature/mi-nueva-feature \
  --title "feature: descripción clara" \
  --body "Resumen del cambio y motivación."
```
> Revisá `CONTRIBUTING.md` antes — exige SwiftFormat 0.58.7 y referenciar issues con `whisky-app/whisky#NNNN`.

---

## 🧰 Formateo y linting

```bash
# Formatear todo el código
swiftformat .

# Verificar sin modificar (lint mode)
swiftformat --lint .

# SwiftLint (corre en cada build automáticamente via run script phase)
swiftlint
```

### Hook pre-commit (opcional pero recomendado)
Copia el hook del repo a tu `.git/hooks/`:
```bash
cp .github/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```
Esto ejecuta SwiftFormat automáticamente antes de cada commit.

---

## 📍 Datos clave para no olvidar

- **No necesitas instalar Wine por separado**. La app lo descarga sola en runtime.
- **Rosetta 2 NO es necesaria** (verificado, no se menciona en ningún lado del repo).
- **Cualquier chip M-series** funciona (M1, M2, M3, M4, M5, A18 Pro — todos Apple Silicon arm64).
- **macOS Tahoe 26.5** funciona aunque el target oficial sea macOS 15+.
- **Branch `main`** = tu fork. Úsalo solo para sincronizar con upstream.
- **Branches `feature/*`** = tu trabajo personal. No las merging a main hasta que estén listas.

---

## 🔗 Links útiles

- Repo original (upstream): https://github.com/frankea/Whisky
- Tu fork: https://github.com/Rilpmcuni/Whisky
- Releases de la app: https://github.com/frankea/Whisky/releases
- Documentación oficial: https://frankea.github.io/Whisky/
- Issues del proyecto original archivado: https://github.com/Whisky-App/Whisky/issues

---

## 📜 Licencia

Este fork mantiene la licencia **GPL-3.0** del proyecto original.
Cualquier distribución pública del código o binarios debe mantener esta licencia.
