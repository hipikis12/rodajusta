#!/usr/bin/env bash
# Gera os arquivos Android padrão do Flutter que não ficam no repositório
# (Gradle, estilos, wrapper) sem sobrescrever os nossos (manifesto, Kotlin,
# ícones), e ajusta o minSdk para 23 (exigido pelo Firebase).
# Uso: tool/preparar_android.sh            (os dois apps)
#      tool/preparar_android.sh operacao   (só um)
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"

preparar() {
  local app="$1"
  echo "==> $app"
  cd "$raiz/apps/$app"
  flutter create --org br.com.rodajusta --project-name "$app" --platforms android . >/dev/null
  local gradle=android/app/build.gradle.kts
  [ -f "$gradle" ] || gradle=android/app/build.gradle
  sed -i.bak -E \
    -e 's/minSdk = flutter\.minSdkVersion/minSdk = 23/' \
    -e 's/minSdkVersion flutter\.minSdkVersion/minSdkVersion 23/' \
    "$gradle"
  rm -f "$gradle.bak"
  grep -Eq 'minSdk(Version)? (= )?23' "$gradle" || { echo "minSdk não encontrado em $gradle" >&2; exit 1; }
}

if [ $# -gt 0 ]; then
  for app in "$@"; do preparar "$app"; done
else
  preparar operacao
  preparar admin
fi
