import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.System;
import Toybox.Math;
using Toybox.Application.Properties;

const GRAPH_WIDTH = 96; // maximum amount of data points we can show in the graph
const DATA_POS_START = GRAPH_WIDTH-1;
class BatteryGuesstimateView extends WatchUi.View {
    var _stepsToShowInGraph as Integer = GRAPH_WIDTH;
    private var _graphData as Array = new [GRAPH_WIDTH];
    private var _dataPos as Integer = DATA_POS_START;
    private var _historyOffset as Integer = 0;
    private var _hasData as Boolean = false;
    private var _batteryStore as BatteryStore = new BatteryStore();
    private var _deviceSpecificView as DeviceView = new DeviceView();
    private var _minBattValue as Float = 100.0;
    private var _maxBattValue as Float = 0.0;
    private var _cumulatedDischarge as Float = 0.0;
    private var _cumulatedCharge as Float = 0.0;
    private var _message as String?;

    private function resetValues() as Void {
        var meta = _batteryStore.getMeta();
        _hasData = (meta.get("newestSeq") as Number)
            >= (meta.get("oldestSeq") as Number);
        _historyOffset = 0;
        _dataPos = DATA_POS_START;
        _minBattValue = 100.0;
        _maxBattValue = 0.0;
        _cumulatedDischarge = 0.0;
        _cumulatedCharge = 0.0;
        _message = null;
    }

    // only for tests
    public function getGraphData() as Array {
        return _graphData;
    }

    // only for tests
    public function getMinBattValue() as Float {
        return _minBattValue;
    }

    // only for tests
    public function getMaxBattValue() as Float {
        return _maxBattValue;
    }

    // only for tests
    public function getCumulatedDischarge() as Float {
        return _cumulatedDischarge;
    }

    // only for tests
    public function getCumulatedCharge() as Float {
        return _cumulatedCharge;
    }

    public function setMessage(message as String?) as Void {
        _message = message;
    }

    //! Constructor
    public function initialize() {
        WatchUi.View.initialize();
    }

    //! Load your resources here
    //! @param dc Device context
    public function onLayout(dc as Dc) as Void {
        setLayout( $.Rez.Layouts.ChartLayout( dc ) );
    }

    //! Restore the state of the app and prepare the view to be shown
    public function onShow() as Void {
        resetValues();
    }

    public function getStepsToShowInGraph() as Integer {
        return _stepsToShowInGraph;
    }

    public function setStepsToShowInGraph(steps as Integer) as Void {
        if (steps < GRAPH_WIDTH) {
            _stepsToShowInGraph = GRAPH_WIDTH;
        } else if (steps > $.MAX_STEPS_TO_CALC) {
            _stepsToShowInGraph = $.MAX_STEPS_TO_CALC;
        } else {
            _stepsToShowInGraph = steps;
        }
        resetValues();
        WatchUi.requestUpdate();
    }

    //! Update the view
    //! @param dc Device Context
    public function onUpdate(dc as Dc) as Void {
        var crossoverOffset = 0;
        if (WatchUi.View has :setClockHandPosition) {
            crossoverOffset = 30;
        }
        if (_message != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            dc.drawText(
                dc.getWidth() / 2, (dc.getHeight() / 2) + 10 + crossoverOffset,
                Graphics.FONT_XTINY,
                _message as String,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        if (!_hasData) {
            dc.drawText(
                dc.getWidth() / 2, (dc.getHeight() / 2) + 10 + crossoverOffset,
                Graphics.FONT_MEDIUM,
                "no data",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            return;
        }
        if (_dataPos >= 0) {
            dc.setPenWidth(20);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
            dc.clear();
            dc.drawText(
                dc.getWidth() / 2, (dc.getHeight() / 2) + 10 + crossoverOffset,
                Graphics.FONT_LARGE,
                "loading ...",
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
            var progress = 360.0/GRAPH_WIDTH*(GRAPH_WIDTH-_dataPos)*-1;
            _deviceSpecificView.drawProgressIndicator(dc, progress as Float, self as View);

            var average = getBatteryDataAverage(_stepsToShowInGraph);
            _graphData[_dataPos] = average;
            if (average != null) {
                if (average < _minBattValue) {
                    _minBattValue = average;
                }
                if (average > _maxBattValue) {
                    _maxBattValue = average;
                }
                if (_dataPos < DATA_POS_START
                    && _graphData[_dataPos + 1] != null) {
                    var nextAverage = _graphData[_dataPos + 1] as Float;
                    if (average > nextAverage) {
                        _cumulatedDischarge += average - nextAverage;
                    }
                    if (average < nextAverage) {
                        _cumulatedCharge += nextAverage - average;
                    }
                }
            }
            _dataPos -= 1;
            WatchUi.requestUpdate();

            return;
        }
        
        dc.setPenWidth(1);
        var timeText = "24h";
        View.onUpdate(dc);

        _deviceSpecificView.drawButtonHint(dc);
        try {
            if (!(Properties.getValue("export-url") as String).equals("")) {
                _deviceSpecificView.drawExportButtonHint(dc);
            }
        } catch (e){
            System.println("Legacy export setting error " + e.getErrorMessage());
        }

        var x;

        for (var i = GRAPH_WIDTH-1; i >= 0; i -= 1) {
            if (_graphData[i] == null) {
                continue;
            }
            x = i * _deviceSpecificView.GRAPH_WIDTH_MULTIPLIER + _deviceSpecificView.X_MARGIN_LEFT;
            var graphData = Math.round(_graphData[i] as Float / 2);
            dc.drawLine(
                x,
                _deviceSpecificView.Y_ZERO_LINE,
                x,
                _deviceSpecificView.Y_ZERO_LINE-graphData  as Float * _deviceSpecificView.GRAPH_WIDTH_MULTIPLIER
            );
        }

        if (_stepsToShowInGraph > 96) {
            timeText = (_stepsToShowInGraph / 96) + "days";
        }

        _deviceSpecificView.drawTimeText(dc, timeText);
        var guesstimate = $.guesstimate(
            _cumulatedDischarge * -1,
            _stepsToShowInGraph * $.SAMPLE_INTERVAL_MINUTES
        );
        var y = _deviceSpecificView.STATS_Y_START;

        dc.drawText(
            _deviceSpecificView.STATS_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            _maxBattValue.format("%0.2f") + "%",
            Graphics.TEXT_JUSTIFY_RIGHT
        );
        y = y + _deviceSpecificView.STATS_LINE_HIGHT;
        dc.drawText(
            _deviceSpecificView.STATS_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            _minBattValue.format("%0.2f") + "%",
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        y = y + _deviceSpecificView.STATS_LINE_HIGHT + _deviceSpecificView.STATS_GROUP_PADDING;
        dc.drawText(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
                "+",
                Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(
            _deviceSpecificView.STATS_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            _cumulatedCharge.format("%0.2f") + "%",
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        y = y + _deviceSpecificView.STATS_LINE_HIGHT;
        dc.drawText(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            "-",
            Graphics.TEXT_JUSTIFY_LEFT
        );
        dc.drawText(
            _deviceSpecificView.STATS_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            _cumulatedDischarge.format("%0.2f") + "%",
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        y = y + _deviceSpecificView.STATS_LINE_HIGHT + _deviceSpecificView.STATS_GROUP_PADDING;
        dc.drawText(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            "->",
            Graphics.TEXT_JUSTIFY_LEFT
        );
        dc.drawText(
            _deviceSpecificView.STATS_X_ALLINGMENT,
            y,
            _deviceSpecificView.STATS_FONT,
            $.guesstimateFormat(guesstimate),
            Graphics.TEXT_JUSTIFY_RIGHT
        );

        // draw min/max symbol
        dc.drawLine(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+3,
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+_deviceSpecificView.STATS_LINE_HIGHT+3
        );
        dc.drawLine(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+6,
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP
        );
        dc.drawLine(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+6,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+6,
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP
        );
        dc.drawLine(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+_deviceSpecificView.STATS_LINE_HIGHT,
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+_deviceSpecificView.STATS_LINE_HIGHT+6
        );
        dc.drawLine(
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+6,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+_deviceSpecificView.STATS_LINE_HIGHT,
            _deviceSpecificView.STATS_ICON_X_ALLINGMENT+3,
            _deviceSpecificView.STATS_MIN_MAX_ARROW_TOP+_deviceSpecificView.STATS_LINE_HIGHT+6
        );
    }

    public function getPartOfStorageBuffer(steps as Integer) as Array {
        return _batteryStore.getBatteryHistory(steps);
    }

    // placed in a seperate function to make it testable
    public function getBatteryDataAverage(stepsToShowInGraph as Integer) as Float? {
        var batteryValue = 0.0;
        var sampleCount = 0;
        var storageValue;
        var stepsPerPixelX = stepsToShowInGraph / GRAPH_WIDTH; // for now it must be dividable by 96

        batteryValue = 0;
        for (var avarageI = stepsPerPixelX; avarageI > 0; avarageI = avarageI-1) {
            storageValue = _batteryStore.getBatteryAt(_historyOffset);
            if (storageValue != null) {
                batteryValue += storageValue;
                sampleCount += 1;
            }
            _historyOffset += 1;
        }
        if (sampleCount == 0) {
            return null;
        }
        return (batteryValue / sampleCount) as Float;
    }
    //! Called when this View is removed from the screen. Save the
    //! state of your app here.
    public function onHide() as Void {
    }
}
