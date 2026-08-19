namespace Telegrama.Dates {

    // Chat list stamps: time today, weekday within the week, date beyond that.
    public string relative (int64 timestamp) {
        if (timestamp <= 0) {
            return "";
        }

        var when = new DateTime.from_unix_local (timestamp);
        var now = new DateTime.now_local ();

        if (when.get_year () == now.get_year () && when.get_day_of_year () == now.get_day_of_year ()) {
            return when.format ("%H:%M");
        }

        if (now.difference (when) < 6 * TimeSpan.DAY) {
            return when.format ("%a");
        }

        return when.format ("%d/%m/%y");
    }
}
