package cl.pilladoempresas.sicomterreno;

import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Base64;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.core.content.FileProvider;

import com.getcapacitor.BridgeActivity;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/**
 * App SICOM (20-11-2026).
 *
 * El contenido es la web de SICOM (https://pilladoiceo.netlify.app). Esta clase
 * agrega lo que un WebView no hace solo y que la web pide a través de
 * window.SICOMNativo (frontend: components/layout/puente-app.tsx):
 *   - guardar un archivo (Excel, PDF, ZIP…) en Descargas y abrirlo,
 *   - imprimir / guardar como PDF,
 *   - abrir links externos en su app (WhatsApp, Maps, navegador),
 * y el botón «atrás» como en cualquier app: vuelve de pantalla y, al llegar al
 * inicio, deja SICOM en segundo plano (no la cierra).
 */
public class MainActivity extends BridgeActivity {

    private static final String HOST_SICOM = "pilladoiceo.netlify.app";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        WebView web = getBridge().getWebView();
        web.addJavascriptInterface(new Puente(this, web), "SICOMNativo");

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView w = getBridge().getWebView();
                if (w.canGoBack()) w.goBack();
                else moveTaskToBack(true);
            }
        });
    }

    /** Lo que la web de SICOM puede pedirle al teléfono. */
    static class Puente {
        private final MainActivity act;
        private final WebView web;

        Puente(MainActivity act, WebView web) {
            this.act = act;
            this.web = web;
        }

        /** Solo responde a la web de SICOM (no a otra página que se abra en el WebView). */
        private boolean origenSicom() {
            final String[] url = { null };
            final Object lock = new Object();
            act.runOnUiThread(() -> {
                synchronized (lock) { url[0] = web.getUrl(); lock.notify(); }
            });
            synchronized (lock) {
                if (url[0] == null) {
                    try { lock.wait(1000); } catch (InterruptedException ignored) { }
                }
            }
            try {
                return url[0] != null && HOST_SICOM.equals(Uri.parse(url[0]).getHost());
            } catch (Exception e) {
                return false;
            }
        }

        @JavascriptInterface
        public String version() {
            return "1";
        }

        @JavascriptInterface
        public void guardarArchivo(String base64, String nombre, String mime) {
            if (!origenSicom()) return;
            try {
                byte[] datos = Base64.decode(base64, Base64.DEFAULT);
                String limpio = nombre == null || nombre.trim().isEmpty() ? "archivo" : nombre.replaceAll("[\\\\/:*?\"<>|]", "_");
                String tipo = mime == null || mime.isEmpty() ? "application/octet-stream" : mime;

                // 1) Copia en Descargas para encontrarlo después (Android 10+ sin permisos).
                boolean enDescargas = false;
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    try {
                        ContentValues cv = new ContentValues();
                        cv.put(MediaStore.Downloads.DISPLAY_NAME, limpio);
                        cv.put(MediaStore.Downloads.MIME_TYPE, tipo);
                        cv.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/SICOM");
                        Uri u = act.getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                        if (u != null) {
                            try (OutputStream os = act.getContentResolver().openOutputStream(u)) {
                                if (os != null) { os.write(datos); enDescargas = true; }
                            }
                        }
                    } catch (Exception ignored) { }
                }

                // 2) Copia privada para abrirlo con la app que corresponda.
                File dir = new File(act.getCacheDir(), "descargas");
                if (!dir.exists()) dir.mkdirs();
                File f = new File(dir, limpio);
                try (FileOutputStream fos = new FileOutputStream(f)) { fos.write(datos); }
                Uri uri = FileProvider.getUriForFile(act, act.getPackageName() + ".fileprovider", f);

                final boolean guardado = enDescargas;
                act.runOnUiThread(() -> {
                    Toast.makeText(act, guardado ? "Guardado en Descargas/SICOM: " + limpio : "Abriendo " + limpio, Toast.LENGTH_SHORT).show();
                    Intent ver = new Intent(Intent.ACTION_VIEW);
                    ver.setDataAndType(uri, tipo);
                    ver.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
                    try {
                        act.startActivity(ver);
                    } catch (ActivityNotFoundException e) {
                        // Sin app para ese tipo: se ofrece compartir (WhatsApp, correo, Drive…).
                        Intent enviar = new Intent(Intent.ACTION_SEND);
                        enviar.setType(tipo);
                        enviar.putExtra(Intent.EXTRA_STREAM, uri);
                        enviar.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        act.startActivity(Intent.createChooser(enviar, "Abrir o compartir " + limpio));
                    }
                });
            } catch (Exception e) {
                act.runOnUiThread(() -> Toast.makeText(act, "No se pudo guardar el archivo", Toast.LENGTH_LONG).show());
            }
        }

        @JavascriptInterface
        public void imprimir(String titulo) {
            if (!origenSicom()) return;
            act.runOnUiThread(() -> {
                try {
                    PrintManager pm = (PrintManager) act.getSystemService(Context.PRINT_SERVICE);
                    String nombre = titulo == null || titulo.isEmpty() ? "SICOM" : titulo;
                    PrintDocumentAdapter adaptador = web.createPrintDocumentAdapter(nombre);
                    pm.print(nombre, adaptador, new PrintAttributes.Builder().build());
                } catch (Exception e) {
                    Toast.makeText(act, "No se pudo abrir la impresión", Toast.LENGTH_LONG).show();
                }
            });
        }

        @JavascriptInterface
        public void abrirExterno(String url) {
            if (!origenSicom() || url == null) return;
            act.runOnUiThread(() -> {
                try {
                    Intent i = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    act.startActivity(i);
                } catch (Exception e) {
                    Toast.makeText(act, "No hay una app para abrir este enlace", Toast.LENGTH_LONG).show();
                }
            });
        }
    }
}
