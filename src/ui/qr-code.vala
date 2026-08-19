// Drawn rather than rendered to an image so the modules stay on exact pixel
// boundaries at any size; a scaled bitmap blurs the edges and scanners suffer.
public class Telegrama.QrCode : Gtk.DrawingArea {

    private const int QUIET_ZONE = 4;

    private QRencode.Code? code = null;
    private string _link = "";

    public string link {
        get {
            return _link;
        }
        set {
            if (_link == value) {
                return;
            }

            _link = value;
            code = value == ""
                ? null
                : QRencode.Code.encode (value, 0, QRencode.EcLevel.M);

            if (value != "" && code == null) {
                warning ("could not encode the login link as a QR code");
            }

            queue_draw ();
        }
    }

    construct {
        set_draw_func (render);
    }

    private void render (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        if (code == null) {
            return;
        }

        var modules = code.width + QUIET_ZONE * 2;

        // Integer scale only, so every module is the same number of pixels.
        var scale = int.min (width, height) / modules;
        if (scale < 1) {
            return;
        }

        var size = scale * modules;
        var ox = (width - size) / 2;
        var oy = (height - size) / 2;

        // Always light-on-dark-agnostic: scanners expect dark modules on a light
        // field, so this does not follow the app's colour scheme.
        cr.set_source_rgb (1.0, 1.0, 1.0);
        cr.rectangle (ox, oy, size, size);
        cr.fill ();

        cr.set_source_rgb (0.0, 0.0, 0.0);
        for (var y = 0; y < code.width; y++) {
            for (var x = 0; x < code.width; x++) {
                if ((code.data[y * code.width + x] & 1) != 0) {
                    cr.rectangle (
                        ox + (x + QUIET_ZONE) * scale,
                        oy + (y + QUIET_ZONE) * scale,
                        scale,
                        scale
                    );
                }
            }
        }
        cr.fill ();
    }
}
