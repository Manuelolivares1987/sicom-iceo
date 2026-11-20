# SICOM Terreno — app Android

App Android (Capacitor 8) que abre las apps de faena de SICOM
(`https://pilladoiceo.netlify.app/m/`) en su propio WebView.

**Por qué existe (20-11-2026):** en Franke un Chrome tenía bloqueados los datos
del sitio y la web no podía guardar sesión ni trabajo sin señal. La app no
depende de la configuración de Chrome, abre desde su ícono y funciona sin
señal con la misma app guardada (service worker) de la web.

- **Contenido:** lo sirve la web. Las mejoras llegan solas; solo se recompila si
  cambia algo nativo (permisos, ícono, configuración).
- **Compilación:** `.github/workflows/app-android.yml` (GitHub Actions). Publica en
  la release fija `sicom-terreno` → `releases/download/sicom-terreno/sicom-terreno.apk`.
- **Instalación:** https://pilladoiceo.netlify.app/instalar/
- **Firma:** llave PKCS12 `sicom-terreno.p12` (alias `sicom-terreno`). NO está en el
  repo: secretos de GitHub `SICOM_KEYSTORE_B64`, `SICOM_KEYSTORE_PASS`,
  `SICOM_KEY_ALIAS`, y copia en el PC de operaciones. **Sin esa llave no se puede
  actualizar la app ya instalada.**
- **Marca:** la app agrega `SICOMTerreno/1` al user agent (`lib/app-terreno.ts`).
