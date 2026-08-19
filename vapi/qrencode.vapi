[CCode (cheader_filename = "qrencode.h")]
namespace QRencode {

	[CCode (cname = "QRecLevel", cprefix = "QR_ECLEVEL_", has_type_id = false)]
	public enum EcLevel {
		L,
		M,
		Q,
		H
	}

	[CCode (cname = "QRcode", free_function = "QRcode_free", has_type_id = false)]
	[Compact]
	public class Code {
		public int version;
		public int width;

		// width * width bytes, one per module; bit 0 is the module colour.
		[CCode (array_length = false)]
		public unowned uint8[] data;

		[CCode (cname = "QRcode_encodeString8bit")]
		public static Code? encode (string text, int version, EcLevel level);
	}
}
