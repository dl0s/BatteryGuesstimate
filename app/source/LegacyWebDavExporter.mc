import Toybox.Communications;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Lang;
using Toybox.Application.Properties;

// Explicitly isolated legacy/manual export path. It does not read or mutate any
// Battery Sync Protocol state and is never invoked automatically.
class LegacyWebDavExporter {
    private var _view as BatteryGuesstimateView;

    public function initialize(view as BatteryGuesstimateView) {
        _view = view;
    }

    private function propertyAsString(key as String) as String {
        try {
            var value = Properties.getValue(key);
            return value == null ? "" : value.toString();
        } catch (e) {
            System.println("LegacyWebDavExporter setting " + key + " error " + e.getErrorMessage());
            return "";
        }
    }

    public function export() as Void {
        var url = propertyAsString("export-url");
        if (url == "") {
            return;
        }
        if (url.length() < 8 || url.substring(0, 8) != "https://") {
            _view.setMessage("URL must start with\n'https://'");
            WatchUi.requestUpdate();
            return;
        }

        var username = propertyAsString("export-username");
        var password = propertyAsString("export-password");
        var headers = {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON};
        if (username != "" || password != "") {
            headers.put("Authorization", "Basic " + StringUtil.encodeBase64(username + ":" + password));
        }
        var params = {
            "battery-history" => _view.getPartOfStorageBuffer(_view.getStepsToShowInGraph())
        } as Dictionary;
        var options = {
            :method => Communications.HTTP_REQUEST_METHOD_PUT,
            :headers => headers
        };
        _view.setMessage("sending...");
        WatchUi.requestUpdate();
        Communications.makeWebRequest(url, params, options, method(:onReceive));
    }

    public function onReceive(
        responseCode as Number,
        data as Dictionary or String or Null
    ) as Void {
        if (responseCode >= 200 && responseCode < 300) {
            _view.setMessage("Done!");
        } else {
            _view.setMessage("ERROR\n'" + responseCode + "'");
            Communications.openWebPage(
                "https://github.com/individual-it/BatteryGuesstimate/#export", null, null
            );
        }
        WatchUi.requestUpdate();
    }
}
