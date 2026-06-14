#!/bin/zsh
#
# ============================================================================
#  instalar-marker-md.sh
# ----------------------------------------------------------------------------
#  Instala y configura "marker" (datalab-to/marker) en macOS de punta a punta:
#
#    1. Verifica/instala los prerequisitos (Homebrew opcional, uv)
#    2. Crea un entorno Python 3.12 aislado en ~/marker-env
#    3. Instala marker-pdf[full]  (PDF, Word, Excel, PowerPoint, EPUB, imágenes)
#    4. Descarga por adelantado los modelos de IA (para que no haya esperas luego)
#    5. Crea los comandos globales: marker_single, marker, marker_chunk_convert
#    6. Crea la Acción Rápida de Automator "Convertir a Markdown (marker)"
#       que aparece al hacer clic derecho en Finder
#    7. Registra el servicio en macOS y refresca Finder
#
#  La carpeta de salida de cada conversión tiene el MISMO NOMBRE del archivo
#  y se crea junto al original.  Ej:  factura.pdf  ->  factura/factura.md
#
#  Es idempotente: puedes ejecutarlo cuantas veces quieras sin romper nada.
#
#  USO:
#       chmod +x instalar-marker-md.sh
#       ./instalar-marker-md.sh
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
#  Helpers de log (con colores)
# ----------------------------------------------------------------------------
AZUL=$'\033[1;34m'; VERDE=$'\033[1;32m'; AMARILLO=$'\033[1;33m'; ROJO=$'\033[1;31m'; FIN=$'\033[0m'
paso()  { print -P "\n${AZUL}==> $1${FIN}"; }
ok()    { print -P "${VERDE}    ✔ $1${FIN}"; }
aviso() { print -P "${AMARILLO}    ⚠ $1${FIN}"; }
err()   { print -P "${ROJO}    ✘ $1${FIN}"; }

# Rutas principales
VENV="$HOME/marker-env"
BIN="$HOME/.local/bin"
WF="$HOME/Library/Services/Convertir a Markdown (marker).workflow"

print -P "${VERDE}################################################################${FIN}"
print -P "${VERDE}#  Instalador de marker + Acción Rápida de Automator (macOS)    #${FIN}"
print -P "${VERDE}################################################################${FIN}"

# ============================================================================
#  PASO 1 — Prerequisitos: uv (gestor de entornos Python)
# ============================================================================
paso "Paso 1/7 — Comprobando 'uv' (gestor de Python)"
if command -v uv >/dev/null 2>&1; then
    ok "uv ya está instalado: $(uv --version)"
else
    aviso "uv no encontrado. Intentando instalarlo…"
    if command -v brew >/dev/null 2>&1; then
        brew install uv
    else
        # Instalador oficial autónomo (no necesita Homebrew)
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # uv se instala en ~/.local/bin
        export PATH="$HOME/.local/bin:$PATH"
    fi
    command -v uv >/dev/null 2>&1 && ok "uv instalado correctamente" || { err "No se pudo instalar uv"; exit 1; }
fi

# ============================================================================
#  PASO 2 — Entorno Python 3.12 aislado en ~/marker-env
# ============================================================================
paso "Paso 2/7 — Creando entorno Python 3.12 en $VENV"
# uv descarga Python 3.12 automáticamente si no lo tienes.
# Idempotente: si ya existe un entorno funcional, lo reutiliza.
if [ -x "$VENV/bin/python" ]; then
    ok "El entorno ya existe en $VENV (se reutiliza)"
else
    uv venv "$VENV" --python 3.12
    ok "Entorno creado en $VENV"
fi

# ============================================================================
#  PASO 3 — Instalar marker-pdf[full]
# ============================================================================
paso "Paso 3/7 — Instalando marker-pdf[full] (puede tardar varios minutos)"
uv pip install --python "$VENV/bin/python" "marker-pdf[full]"
"$VENV/bin/python" -c "import marker" && ok "marker-pdf[full] instalado" || { err "Fallo al importar marker"; exit 1; }

# ============================================================================
#  PASO 4 — Descargar los modelos de IA por adelantado (~3 GB, una sola vez)
# ============================================================================
paso "Paso 4/7 — Descargando los modelos de IA (layout, OCR, tablas…)"
aviso "La primera vez baja ~3 GB. Si ya los tienes en caché, será instantáneo."
"$VENV/bin/python" -c "from marker.models import create_model_dict; create_model_dict()" \
    && ok "Modelos listos en ~/Library/Caches/datalab" \
    || aviso "No se pudieron pre-descargar (se bajarán solos en la primera conversión)"

# ============================================================================
#  PASO 5 — Comandos globales en ~/.local/bin (y asegurar que está en el PATH)
# ============================================================================
paso "Paso 5/7 — Creando comandos globales en $BIN"
mkdir -p "$BIN"
ln -sf "$VENV/bin/marker_single"        "$BIN/marker_single"
ln -sf "$VENV/bin/marker"               "$BIN/marker"
ln -sf "$VENV/bin/marker_chunk_convert" "$BIN/marker_chunk_convert" 2>/dev/null || true
ok "Enlaces creados: marker_single, marker, marker_chunk_convert"

# Asegurar que ~/.local/bin esté en el PATH (vía ~/.zshrc)
if ! grep -q 'HOME/.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    print '\n# marker: comandos en ~/.local/bin' >> "$HOME/.zshrc"
    print 'export PATH="$HOME/.local/bin:$PATH"'  >> "$HOME/.zshrc"
    aviso "Añadido ~/.local/bin al PATH en ~/.zshrc (abre una terminal nueva para que aplique)"
else
    ok "~/.local/bin ya está en tu PATH"
fi

# ============================================================================
#  PASO 6 — Acción Rápida de Automator (clic derecho en Finder)
# ============================================================================
paso "Paso 6/7 — Creando la Acción Rápida de Automator"
rm -rf "$WF"
mkdir -p "$WF/Contents"

# --- Info.plist : nombre del menú + tipos de archivo que lo activan ---------
cat > "$WF/Contents/Info.plist" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSIconName</key>
			<string>NSActionTemplate</string>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>Convertir a Markdown (marker)</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict>
				<key>NSApplicationIdentifier</key>
				<string>com.apple.finder</string>
			</dict>
			<key>NSSendFileTypes</key>
			<array>
				<string>com.adobe.pdf</string>
				<string>org.openxmlformats.wordprocessingml.document</string>
				<string>com.microsoft.word.doc</string>
				<string>org.openxmlformats.spreadsheetml.sheet</string>
				<string>com.microsoft.excel.xls</string>
				<string>org.openxmlformats.presentationml.presentation</string>
				<string>com.microsoft.powerpoint.ppt</string>
				<string>org.idpf.epub-container</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
PLIST_EOF

# --- document.wflow : el flujo con el script de conversión ------------------
#  Nota: el heredoc va entre comillas ('WFLOW_EOF') para que las variables
#  del script ($HOME, $@, $#, etc.) se guarden LITERALES y las interprete
#  Automator, no este instalador.  Los símbolos &gt; y &amp; son el escape
#  XML de  >  y  &  dentro del .plist.
cat > "$WF/Contents/document.wflow" <<'WFLOW_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>521</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMParameterProperties</key>
				<dict>
					<key>COMMAND_STRING</key>
					<dict/>
					<key>CheckedForUserDefaultShell</key>
					<dict/>
					<key>inputMethod</key>
					<dict/>
					<key>shell</key>
					<dict/>
					<key>source</key>
					<dict/>
				</dict>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.path</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
MARKER="$HOME/marker-env/bin/marker_single"
total=$#
count=0
osascript -e "display notification \"Convirtiendo $total archivo(s) a Markdown…\" with title \"Marker\""
for f in "$@"; do
  dir="$(dirname "$f")"
  # La carpeta de salida lleva el mismo nombre del archivo (marker la crea dentro de "$dir")
  "$MARKER" "$f" --output_dir "$dir" &gt;/dev/null 2&gt;&amp;1 &amp;&amp; count=$((count + 1))
done
osascript -e "display notification \"$count de $total convertido(s)\" with title \"Marker\" subtitle \"Markdown listo junto al archivo original\" sound name \"Glass\""</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>25915126-1290-417F-B286-D747B745B5A2</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>ABE22233-C961-4CAD-A61C-736317CF0A64</string>
				<key>UUID</key>
				<string>B1624260-B59E-423A-9020-E41D3BE4EB58</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/sh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.000000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsForInputAndAction</key>
		<array>
			<string>com.apple.finder</string>
		</array>
		<key>applicationBundleIDsForInput</key>
		<array>
			<string>com.apple.finder</string>
		</array>
		<key>serviceApplicationBundleID</key>
		<string>com.apple.finder</string>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.fileSystemObject</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW_EOF

# Validar que los plists están bien formados
plutil -lint "$WF/Contents/Info.plist"     >/dev/null && ok "Info.plist válido"
plutil -lint "$WF/Contents/document.wflow"  >/dev/null && ok "document.wflow válido"

# ============================================================================
#  PASO 7 — Registrar el servicio y refrescar Finder
# ============================================================================
paso "Paso 7/7 — Registrando el servicio en macOS"
/System/Library/CoreServices/pbs -update 2>/dev/null || true
killall Finder 2>/dev/null || true
ok "Servicio registrado y Finder reiniciado"

# ============================================================================
#  FIN
# ============================================================================
print -P "\n${VERDE}################################################################${FIN}"
print -P "${VERDE}#  ¡Instalación completada!                                     #${FIN}"
print -P "${VERDE}################################################################${FIN}"
cat <<'FINAL'

CÓMO USAR
---------
  • Desde la terminal:
        marker_single archivo.pdf --output_dir salida/
        marker carpeta_de_pdfs/   --output_dir salida/

  • Desde Finder (clic derecho):
        Selecciona uno o varios archivos (PDF, Word, Excel, PPT, EPUB)
        -> clic derecho -> "Convertir a Markdown (marker)"
        (puede estar dentro del submenú "Servicios" / "Acciones rápidas")

  El resultado se guarda en una carpeta con el MISMO NOMBRE del archivo,
  junto al original.  Ej:  ~/Docs/factura.pdf  ->  ~/Docs/factura/factura.md

NOTAS
-----
  • La primera conversión de cada sesión tarda un poco (carga modelos).
  • Si la acción no aparece: Ajustes del Sistema -> Extensiones ->
    Acciones rápidas, y actívala.

FINAL
