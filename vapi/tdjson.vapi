[CCode (cheader_filename = "td/telegram/td_json_client.h")]
namespace TDJson {

	[CCode (cname = "td_create_client_id")]
	public int create_client_id ();

	[CCode (cname = "td_send")]
	public void send (int client_id, string request);

	// Only one thread may ever call this. The returned string is valid until that
	// thread's next receive/execute, so copy or parse it immediately.
	[CCode (cname = "td_receive")]
	public unowned string? receive (double timeout);

	[CCode (cname = "td_execute")]
	public unowned string? execute (string request);
}
