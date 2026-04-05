#!/usr/bin/env bash

# ─────────────────────────────────────────────────────────────────────────────
#  Yopass – Custom Build Script
#  Repository: https://github.com/Trustfuly/fluffy-invention
#
#  What this script does:
#    1. Clones the latest jhaals/yopass source
#    2. Adds Ukrainian translation (uk.json)
#    3. Sets Ukrainian as the default language (fallback: English)
#    4. Builds the frontend (React/Vite)
#    5. Builds yopass-server binary from source
#    6. Copies built assets and binary into this repo
#
#  Requirements:
#    - Node.js >= 18
#    - npm
#    - git
#    - curl
#    - go >= 1.21
#
#  Usage:
#    bash build.sh
#    bash build.sh --push    # also commits and pushes to GitHub
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_USER="Trustfuly"
REPO_NAME="fluffy-invention"
YOPASS_REPO="https://github.com/jhaals/yopass.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/yopass-build-$$"
PUSH=false

[[ "${1:-}" == "--push" ]] && PUSH=true

# ─── Colors ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg_info()  { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
msg_error() { echo -e "  \033[0;31m[ERROR]\033[0m $1"; exit 1; }

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

# ─── Check requirements ───────────────────────────────────────────────────────
msg_info "Checking requirements"
command -v node >/dev/null || msg_error "Node.js is not installed."
command -v npm  >/dev/null || msg_error "npm is not installed."
command -v git  >/dev/null || msg_error "git is not installed."
command -v curl >/dev/null || msg_error "curl is not installed."
command -v go   >/dev/null || msg_error "Go is not installed."
msg_ok "All requirements satisfied (Node $(node --version), Go $(go version | awk '{print $3}'))"

# ─── Get latest yopass version ───────────────────────────────────────────────
msg_info "Fetching latest yopass release info"
RELEASE=$(curl -fsSL https://api.github.com/repos/jhaals/yopass/releases/latest \
  | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
[[ -z "$RELEASE" ]] && msg_error "Could not determine latest yopass release."
msg_ok "Latest yopass version: ${RELEASE}"

# ─── Clone yopass source ─────────────────────────────────────────────────────
msg_info "Cloning jhaals/yopass (tag: ${RELEASE})"
mkdir -p "$BUILD_DIR"
git clone --depth=1 --branch "$RELEASE" "$YOPASS_REPO" "$BUILD_DIR/yopass" 2>/dev/null \
  || git clone --depth=1 "$YOPASS_REPO" "$BUILD_DIR/yopass" 2>/dev/null
msg_ok "Cloned yopass source"

WEBSITE_DIR="$BUILD_DIR/yopass/website"
LOCALES_DIR="$WEBSITE_DIR/src/shared/locales"
I18N_FILE="$WEBSITE_DIR/src/shared/lib/i18n.ts"

# ─── Add Ukrainian translation ───────────────────────────────────────────────
msg_info "Adding Ukrainian translation (uk.json)"
cat >"$LOCALES_DIR/uk.json" <<'UKJSON'
{
  "create": {
    "title": "Зашифрувати повідомлення",
    "inputSecretLabel": "Ваш секрет",
    "inputSecretPlaceholder": "Введіть ваш секрет...",
    "buttonEncrypt": "Зашифрувати повідомлення",
    "inputCustomPasswordLabel": "Власний пароль",
    "inputCustomPasswordPlaceholder": "Введіть ваш пароль...",
    "inputOneTimeLabel": "Одноразове завантаження",
    "inputGenerateKeyLabel": "Згенерувати ключ розшифрування"
  },
  "upload": {
    "title": "Завантажити файл",
    "buttonUpload": "Завантажити",
    "uploadFileButton": "Завантажити файл",
    "dragDropText": "Перетягніть або натисніть, щоб вибрати файл",
    "maxFileSize": "Максимальний розмір файлу: {{size}}",
    "errorSelectFile": "Будь ласка, виберіть файл для завантаження",
    "errorFailedToRead": "Не вдалося прочитати файл",
    "expirationLegendFile": "Зашифрований файл буде автоматично видалено через",
    "fileTooLarge": "Файл перевищує максимально допустимий розмір {{maxSize}}"
  },
  "display": {
    "titleDecrypting": "Розшифрування...",
    "titleDecryptionKey": "Введіть ключ розшифрування",
    "captionDecryptionKey": "Не оновлюйте цю сторінку, оскільки секрет може бути обмежений одноразовим завантаженням.",
    "inputDecryptionKeyPlaceholder": "Ключ розшифрування",
    "inputDecryptionKeyLabel": "Необхідний ключ розшифрування, введіть його нижче",
    "errorInvalidPassword": "Невірний пароль, спробуйте ще раз",
    "buttonDecrypt": "Розшифрувати секрет",
    "decryptingMessage": "Розшифровування вашого секрету…",
    "errorInvalidPasswordDetailed": "Невірний пароль. Спробуйте ще раз.",
    "buttonDecryptSecret": "РОЗШИФРУВАТИ СЕКРЕТ",
    "loading": "Завантаження...",
    "secureMessageTitle": "Захищене повідомлення",
    "secureMessageSubtitle": "Ви отримали захищене повідомлення, яке можна переглянути лише один раз",
    "importantTitle": "Важливо",
    "oneTimeWarning": "Це повідомлення самознищиться після перегляду. Після розкриття воно більше не буде доступне.",
    "oneTimeWarningReady": "Переконайтеся, що ви готові переглянути його зараз.",
    "buttonRevealMessage": "Показати захищене повідомлення"
  },
  "error": {
    "title": "Секрет не існує",
    "subtitle": "Це може бути спричинено будь-якою з цих причин.",
    "titleOpened": "Вже відкрито",
    "subtitleOpenedBefore": "Секрет може бути обмежений одним завантаженням. Він міг бути втрачений, оскільки відправник перейшов за цим посиланням до вас.",
    "subtitleOpenedCompromised": "Секрет міг бути скомпрометований і прочитаний кимось іншим. Зверніться до відправника та запросіть новий секрет.",
    "titleBrokenLink": "Пошкоджене посилання",
    "subtitleBrokenLink": "Посилання має збігатися ідеально, щоб розшифрування працювало, можливо, відсутні деякі символи.",
    "titleExpired": "Термін дії минув",
    "subtitleExpired": "Жоден секрет не існує вічно. Усі збережені секрети мають термін дії і будуть автоматично видалені після закінчення. Термін зберігання — від однієї години до одного тижня."
  },
  "result": {
    "title": "Секрет надійно збережено",
    "subtitle": "Ваш секрет зашифровано і збережено. Поділіться цими посиланнями для надання доступу.",
    "subtitleDownloadOnce": "Секрет можна завантажити лише один раз. Не відкривайте посилання самостійно. Обережні користувачі надсилають ключ розшифрування окремим каналом зв'язку.",
    "reminderTitle": "Пам'ятайте",
    "rowLabelOneClick": "Посилання в один клік",
    "rowOneClickDescription": "Поділіться цим посиланням для прямого доступу до секрету",
    "rowLabelShortLink": "Коротке посилання",
    "rowShortLinkDescription": "Вимагає окремої передачі ключа розшифрування",
    "rowLabelDecryptionKey": "Ключ розшифрування",
    "rowDecryptionKeyDescription": "Необхідний для розшифрування повідомлення з коротким посиланням",
    "buttonCreateAnother": "Створити ще один секрет"
  },
  "secret": {
    "titleFile": "Файл завантажено",
    "subtitleFile": "Ваш файл розшифровано і завантажено. Якщо вам потрібно завантажити його знову, натисніть кнопку нижче.",
    "fileDownloaded": "Файл завантажено",
    "buttonDownloadFile": "Завантажити файл ще раз",
    "titleMessage": "Розшифроване повідомлення",
    "subtitleMessage": "Цей секрет більше не буде доступний. Обов'язково збережіть його зараз!",
    "buttonCopy": "Копіювати",
    "buttonCopyToClipboard": "Копіювати в буфер обміну",
    "buttonCopied": "Скопійовано!",
    "showQrCode": "Показати QR-код",
    "hideQrCode": "Приховати QR-код"
  },
  "delete": {
    "buttonDelete": "Видалити",
    "messageDeleted": "Секрет видалено з сервера!",
    "dialogTitle": "Видалити секрет?",
    "dialogMessage": "Ви впевнені, що хочете видалити цей секрет?",
    "dialogProgress": "Видалення...",
    "dialogConfirm": "Видалити",
    "dialogCancel": "Скасувати"
  },
  "expiration": {
    "legend": "Автоматично видаляється через",
    "optionOneHourLabel": "Одна година",
    "optionOneDayLabel": "Один день",
    "optionOneWeekLabel": "Один тиждень"
  },
  "features": {
    "title": "Діліться секретами безпечно та легко",
    "subtitle": "Yopass створено для зменшення кількості паролів у відкритому вигляді в електронній пошті та чатах шляхом шифрування та генерації короткострокового посилання, яке можна переглянути лише один раз.",
    "featureEndToEndTitle": "Наскрізне шифрування",
    "featureEndToEndText": "Шифрування та розшифрування виконуються локально в браузері. Ключ ніколи не зберігається в Yopass.",
    "featureSelfDestructionTitle": "Самознищення",
    "featureSelfDestructionText": "Зашифровані повідомлення мають фіксований термін дії і будуть автоматично видалені після його закінчення.",
    "featureOneTimeTitle": "Одноразові завантаження",
    "featureOneTimeText": "Зашифроване повідомлення можна завантажити лише один раз, що знижує ризик перегляду ваших секретів сторонніми.",
    "featureSimpleSharingTitle": "Простий обмін",
    "featureSimpleSharingText": "Yopass генерує унікальне посилання в один клік для зашифрованого файлу або повідомлення. Пароль розшифрування можна надіслати окремо.",
    "featureNoAccountsTitle": "Не потрібні облікові записи",
    "featureNoAccountsText": "Обмін має бути швидким і простим; у базі даних зберігається лише зашифрований секрет, без додаткової інформації.",
    "featureOpenSourceTitle": "Програмне забезпечення з відкритим кодом",
    "featureOpenSourceText": "Механізм шифрування Yopass побудований на програмному забезпеченні з відкритим кодом, що забезпечує повну прозорість з можливістю аудиту та внесення змін."
  },
  "header": {
    "buttonHome": "Головна",
    "buttonUpload": "Завантажити",
    "buttonText": "Текст",
    "appName": "Yopass"
  },
  "common": {
    "copy": "Копіювати",
    "copied": "Скопійовано!"
  },
  "footer": {
    "privacyNotice": "Політика конфіденційності",
    "imprint": "Імпресум",
    "createdBy": "Створено"
  },
  "readOnly": {
    "title": "Отримання секрету",
    "description": "Цей екземпляр налаштований лише для отримання секретів. Щоб переглянути секрет, вам потрібне повне посилання."
  }
}
UKJSON
msg_ok "Ukrainian translation added"

# ─── Update locales/index.ts ─────────────────────────────────────────────────
msg_info "Updating locales/index.ts"
cat >"$LOCALES_DIR/index.ts" <<'EOF'
export { default as en } from './en.json';
export { default as uk } from './uk.json';
export { default as sv } from './sv.json';
export { default as de } from './de.json';
export { default as pl } from './pl.json';
export { default as by } from './by.json';
export { default as ru } from './ru.json';
export { default as fr } from './fr.json';
export { default as nl } from './nl.json';
export { default as es } from './es.json';
export { default as no } from './no.json';
export { default as cs } from './cs.json';
EOF
msg_ok "locales/index.ts updated (uk added)"

# ─── Update i18n.ts ──────────────────────────────────────────────────────────
msg_info "Updating i18n.ts"
cat >"$I18N_FILE" <<'EOF'
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';
import LanguageDetector from 'i18next-browser-languagedetector';
import { en, uk, sv, no, de, cs, pl, by, ru, fr, nl, es } from '../locales';

i18n
  .use(initReactI18next)
  .use(LanguageDetector)
  .init({
    resources: {
      en: { translation: en },
      uk: { translation: uk },
      sv: { translation: sv },
      no: { translation: no },
      de: { translation: de },
      cs: { translation: cs },
      pl: { translation: pl },
      by: { translation: by },
      ru: { translation: ru },
      fr: { translation: fr },
      nl: { translation: nl },
      es: { translation: es },
    },
    fallbackLng: 'en',
    lng: 'uk',
    debug: false,
    interpolation: { escapeValue: false },
    detection: {
      order: ['localStorage', 'navigator', 'htmlTag'],
      caches: [],
    },
  });

export default i18n;
EOF
msg_ok "i18n.ts updated (uk added, uk as default)"

# ─── Patch LanguageSwitcher.tsx — add Ukrainian ──────────────────────────────
msg_info "Patching LanguageSwitcher.tsx"
LANG_SWITCHER="$WEBSITE_DIR/src/shared/components/LanguageSwitcher.tsx"
sed -i "s/{ code: 'en', name: 'English' },/{ code: 'en', name: 'English' },\n    { code: 'uk', name: 'Українська' },/" "$LANG_SWITCHER"
msg_ok "LanguageSwitcher.tsx patched (uk added)"

# ─── Build frontend ───────────────────────────────────────────────────────────
msg_info "Installing npm dependencies"
cd "$WEBSITE_DIR"
npm install --legacy-peer-deps --silent
msg_ok "Dependencies installed"

msg_info "Building frontend"
npm run build --silent
msg_ok "Frontend built successfully"

# ─── Copy built assets to repo ───────────────────────────────────────────────
msg_info "Copying frontend assets to repo"
rm -rf "$SCRIPT_DIR/public"
cp -r "$WEBSITE_DIR/dist" "$SCRIPT_DIR/public"
msg_ok "Frontend assets copied to public/"

# ─── Build yopass-server binary ──────────────────────────────────────────────
msg_info "Building yopass-server binary from source"
mkdir -p "$SCRIPT_DIR/bin"
cd "$BUILD_DIR/yopass"
go build -o "$SCRIPT_DIR/bin/yopass-server" ./cmd/yopass-server
chmod +x "$SCRIPT_DIR/bin/yopass-server"
msg_ok "yopass-server binary built and saved to bin/"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║          ✅  Build completed successfully!               ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║   📦  Yopass version : %-34s ║\n" "${RELEASE}"           ║
echo "  ║   🇺🇦  Language       : Ukrainian (default) + all others  ║"
echo "  ║   ✅  Added          : Ukrainian (uk)                    ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
echo "  ║   Output:                                                ║"
echo "  ║     public/   ← frontend assets                          ║"
echo "  ║     bin/      ← yopass-server binary                     ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo -e "\033[0m"

# ─── Git push ─────────────────────────────────────────────────────────────────
if [[ "$PUSH" == "true" ]]; then
  msg_info "Committing and pushing to GitHub"
  cd "$SCRIPT_DIR"
  git add public/ bin/ build.sh
  git commit -m "build: update to yopass ${RELEASE} with Ukrainian UI"
  git push origin main
  msg_ok "Pushed to github.com/${REPO_USER}/${REPO_NAME}"
fi
