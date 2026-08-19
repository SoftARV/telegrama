int main (string[] args) {
	var loop = new MainLoop ();
	var client = new Telegrama.Td.Client ();
	var status = 0;

	client.start ();

	probe.begin (client, (obj, res) => {
		status = probe.end (res);
		loop.quit ();
	});

	loop.run ();
	return status;
}

async int probe (Telegrama.Td.Client client) {
	var status = 0;

	try {
		var option = yield client.request ("getOption", (b) => {
			b.set_member_name ("name");
			b.add_string_value ("version");
		});
		print ("telegrama %s — TDLib %s\n",
			Telegrama.Config.VERSION,
			option.get_string_member ("value"));
	} catch (Error e) {
		printerr ("telegrama: %s\n", e.message);
		status = 1;
	}

	yield client.stop ();
	return status;
}
