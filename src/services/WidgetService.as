package services
{
	import com.adobe.utils.StringUtil;
	import com.spikeapp.spike.airlibrary.SpikeANE;
	
	import flash.events.Event;
	import flash.utils.Dictionary;
	import flash.utils.setInterval;
	
	import database.BgReading;
	import database.BlueToothDevice;
	import database.Calibration;
	import database.CommonSettings;
	
	import events.CalibrationServiceEvent;
	import events.FollowerEvent;
	import events.SettingsServiceEvent;
	import events.TransmitterServiceEvent;
	import events.TreatmentsEvent;
	
	import model.ModelLocator;
	
	import starling.core.Starling;
	
	import treatments.TreatmentsManager;
	
	import ui.chart.GlucoseFactory;
	
	import utils.BgGraphBuilder;
	import utils.DeviceInfo;
	import utils.GlucoseHelper;
	import utils.MathHelper;
	import utils.SpikeJSON;
	import utils.TimeSpan;
	import utils.Trace;

	[ResourceBundle("generalsettingsscreen")]
	[ResourceBundle("widgetservice")]
	[ResourceBundle("chartscreen")]
	[ResourceBundle("treatments")]
	
	public class WidgetService
	{
		/* Constants */
		private static const TIME_1_HOUR:int = 60 * 60 * 1000;
		private static const TIME_2_HOURS:int = 2 * 60 * 60 * 1000;
		private static const TIME_1_MINUTE:int = 60 * 1000;
		
		/* Internal Variables */
		private static var displayTrendEnabled:Boolean = true;
		private static var displayDeltaEnabled:Boolean = true;
		private static var displayUnitsEnabled:Boolean = true;
		private static var initialGraphDataSet:Boolean = false;
		private static var dateFormat:String;
		private static var historyTimespan:int;
		private static var widgetHistory:int;
		private static var glucoseUnit:String;
		
		/* Objects */
		private static var months:Array;
		private static var startupGlucoseReadingsList:Array;
		private static var activeGlucoseReadingsList:Array = [];
		
		public function WidgetService()
		{
			throw new Error("WidgetService is not meant to be instantiated!");
		}
		
		public static function init():void
		{
			Trace.myTrace("WidgetService.as", "Service started!");
			
			SpikeANE.initUserDefaults();
			
			if (!BlueToothDevice.isFollower())
				Starling.juggler.delayCall(setInitialGraphData, 3);
			
			CommonSettings.instance.addEventListener(SettingsServiceEvent.SETTING_CHANGED, onSettingsChanged);
			TransmitterService.instance.addEventListener(TransmitterServiceEvent.BGREADING_EVENT, onBloodGlucoseReceived);
			NightscoutService.instance.addEventListener(FollowerEvent.BG_READING_RECEIVED, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.NEW_CALIBRATION_EVENT, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, onBloodGlucoseReceived);
			CalibrationService.instance.addEventListener(CalibrationServiceEvent.INITIAL_CALIBRATION_EVENT, setInitialGraphData);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_ADDED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_DELETED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.TREATMENT_UPDATED, onTreatmentRefresh);
			TreatmentsManager.instance.addEventListener(TreatmentsEvent.IOB_COB_UPDATED, onTreatmentRefresh);
			
			setInterval(updateTreatments, TIME_1_MINUTE);
		}
		
		private static function onSettingsChanged(e:SettingsServiceEvent):void
		{
			if (e.data == CommonSettings.COMMON_SETTING_DO_MGDL ||
				e.data == CommonSettings.COMMON_SETTING_URGENT_LOW_MARK ||
				e.data == CommonSettings.COMMON_SETTING_LOW_MARK ||
				e.data == CommonSettings.COMMON_SETTING_HIGH_MARK ||
				e.data == CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK ||
				e.data == CommonSettings.COMMON_SETTING_CHART_DATE_FORMAT || 
				e.data == CommonSettings.COMMON_SETTING_WIDGET_HISTORY_TIMESPAN ||
				e.data == CommonSettings.COMMON_SETTING_APP_LANGUAGE
			)
			{
				setInitialGraphData();
			}
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE)
				SpikeANE.setUserDefaultsData("smoothLine", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS)
				SpikeANE.setUserDefaultsData("showMarkers", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL)
				SpikeANE.setUserDefaultsData("showMarkerLabel", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES)
				SpikeANE.setUserDefaultsData("showGridLines", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS)
				SpikeANE.setUserDefaultsData("lineThickness", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS)
				SpikeANE.setUserDefaultsData("markerRadius", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)
				SpikeANE.setUserDefaultsData("urgentHighColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)
				SpikeANE.setUserDefaultsData("highColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)
				SpikeANE.setUserDefaultsData("inRangeColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)
				SpikeANE.setUserDefaultsData("lowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)
				SpikeANE.setUserDefaultsData("urgenLowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)
				SpikeANE.setUserDefaultsData("markerColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)
				SpikeANE.setUserDefaultsData("axisColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)
				SpikeANE.setUserDefaultsData("axisFontColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)
				SpikeANE.setUserDefaultsData("backgroundColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)
				SpikeANE.setUserDefaultsData("backgroundOpacity", String(Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)) / 100));
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)
				SpikeANE.setUserDefaultsData("gridLinesColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)
				SpikeANE.setUserDefaultsData("displayLabelsColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)).toString(16).toUpperCase());
			else if (e.data == CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)
				SpikeANE.setUserDefaultsData("oldDataColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)).toString(16).toUpperCase());
		}
		
		private static function setInitialGraphData(e:Event = null):void
		{
			Trace.myTrace("WidgetService.as", "Setting initial widget data!");
			
			months = ModelLocator.resourceManagerInstance.getString('widgetservice','months').split(",");
			
			dateFormat = CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_CHART_DATE_FORMAT);
			historyTimespan = int(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HISTORY_TIMESPAN));
			widgetHistory = historyTimespan * TIME_1_HOUR;
			activeGlucoseReadingsList = [];
			
			startupGlucoseReadingsList = ModelLocator.bgReadings.concat();
			var now:Number = new Date().valueOf();
			var latestGlucoseReading:BgReading = startupGlucoseReadingsList[startupGlucoseReadingsList.length - 1];
			var lowestPossibleMmolValue:Number = Math.round(((BgReading.mgdlToMmol((40))) * 10)) / 10;
			var highestPossibleMmolValue:Number = Math.round(((BgReading.mgdlToMmol((400))) * 10)) / 10;
			
			for(var i:int = startupGlucoseReadingsList.length - 1 ; i >= 0; i--)
			{
				var timestamp:Number = (startupGlucoseReadingsList[i] as BgReading).timestamp;
				
				if (now - timestamp <= widgetHistory)
				{
					var currentReading:BgReading = startupGlucoseReadingsList[i] as BgReading;
					if (currentReading == null || currentReading.calculatedValue == 0 || (currentReading.calibration == null && !BlueToothDevice.isFollower()))
						continue;
					
					var glucose:String = BgGraphBuilder.unitizedString((startupGlucoseReadingsList[i] as BgReading).calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true");
					var glucoseValue:Number = Number(glucose);
					if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
					{
						if (isLowValue(glucose) || glucoseValue < 40)
							glucoseValue = 38;
						else if (glucose == "HIGH" || glucoseValue > 400)
							glucoseValue = 400;
					}
					else
					{
						
						if (isLowValue(glucose) || glucoseValue < lowestPossibleMmolValue)
							glucoseValue = lowestPossibleMmolValue;
						else if (glucose == "HIGH" || glucoseValue > highestPossibleMmolValue)
							glucoseValue = highestPossibleMmolValue;
					}
					
					activeGlucoseReadingsList.push( { value: glucoseValue, time: getGlucoseTimeFormatted(timestamp, true), timestamp: timestamp } );
				}
				else
					break;
			}
			
			activeGlucoseReadingsList.reverse();
			processChartGlucoseValues();
			
			//Graph Data
			SpikeANE.setUserDefaultsData("chartData", SpikeJSON.stringify(activeGlucoseReadingsList));
			
			//Settings
			SpikeANE.setUserDefaultsData("smoothLine", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SMOOTH_LINE));
			SpikeANE.setUserDefaultsData("showMarkers", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKERS));
			SpikeANE.setUserDefaultsData("showMarkerLabel", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_MARKER_LABEL));
			SpikeANE.setUserDefaultsData("showGridLines", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_SHOW_GRID_LINES));
			SpikeANE.setUserDefaultsData("lineThickness", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LINE_THICKNESS));
			SpikeANE.setUserDefaultsData("markerRadius", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MARKER_RADIUS));
			
			//Display Labels Data
			if (latestGlucoseReading != null)
			{
				var timeFormatted:String = getGlucoseTimeFormatted(latestGlucoseReading.timestamp, false);
				var lastUpdate:String = getLastUpdate(latestGlucoseReading.timestamp) + ", " + timeFormatted;
				SpikeANE.setUserDefaultsData("latestWidgetUpdate", ModelLocator.resourceManagerInstance.getString('widgetservice','last_update_label') + " " + lastUpdate);
				SpikeANE.setUserDefaultsData("latestGlucoseTime", String(latestGlucoseReading.timestamp));
				SpikeANE.setUserDefaultsData("latestGlucoseValue", BgGraphBuilder.unitizedString(latestGlucoseReading.calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true"));
				SpikeANE.setUserDefaultsData("latestGlucoseSlopeArrow", latestGlucoseReading.slopeArrow());
				SpikeANE.setUserDefaultsData("latestGlucoseDelta", MathHelper.formatNumberToStringWithPrefix(Number(BgGraphBuilder.unitizedDeltaString(false, true))));
			}
			
			//Threshold Values
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
			{
				SpikeANE.setUserDefaultsData("urgenLowThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_LOW_MARK));
				SpikeANE.setUserDefaultsData("lowThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_LOW_MARK));
				SpikeANE.setUserDefaultsData("highThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_HIGH_MARK));
				SpikeANE.setUserDefaultsData("urgentHighThreshold", CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK));
			}
			else
			{
				SpikeANE.setUserDefaultsData("urgenLowThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_LOW_MARK))))) * 10)) / 10));
				SpikeANE.setUserDefaultsData("lowThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_LOW_MARK))))) * 10)) / 10));
				SpikeANE.setUserDefaultsData("highThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_HIGH_MARK))))) * 10)) / 10));
				SpikeANE.setUserDefaultsData("urgentHighThreshold", String(Math.round(((BgReading.mgdlToMmol((Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_URGENT_HIGH_MARK))))) * 10)) / 10));
			}
				
			//Colors
			SpikeANE.setUserDefaultsData("urgenLowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_LOW_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("lowColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_LOW_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("inRangeColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_IN_RANGE_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("highColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_HIGH_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("urgentHighColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_URGENT_HIGH_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("oldDataColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_OLD_DATA_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("displayLabelsColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_DISPLAY_LABELS_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("markerColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GLUCOSE_MARKER_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("axisColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("axisFontColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_AXIS_FONT_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("gridLinesColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_GRID_LINES_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("mainLineColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_MAIN_LINE_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("backgroundColor", "#" + uint(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_COLOR)).toString(16).toUpperCase());
			SpikeANE.setUserDefaultsData("backgroundOpacity", String(Number(CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_WIDGET_BACKGROUND_OPACITY)) / 100));
			
			//Glucose Unit
			SpikeANE.setUserDefaultsData("glucoseUnit", GlucoseHelper.getGlucoseUnit());
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
				SpikeANE.setUserDefaultsData("glucoseUnitInternal", "mgdl");
			else
				SpikeANE.setUserDefaultsData("glucoseUnitInternal", "mmol");
			
			//IOB & COB
			SpikeANE.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			SpikeANE.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
			
			//Translations
			SpikeANE.setUserDefaultsData("minAgo", ModelLocator.resourceManagerInstance.getString('widgetservice','minute_ago'));
			SpikeANE.setUserDefaultsData("hourAgo", ModelLocator.resourceManagerInstance.getString('widgetservice','hour_ago'));
			SpikeANE.setUserDefaultsData("ago", ModelLocator.resourceManagerInstance.getString('widgetservice','ago'));
			SpikeANE.setUserDefaultsData("now", ModelLocator.resourceManagerInstance.getString('widgetservice','now'));
			SpikeANE.setUserDefaultsData("openSpike", ModelLocator.resourceManagerInstance.getString('widgetservice','open_spike'));
			SpikeANE.setUserDefaultsData("high", ModelLocator.resourceManagerInstance.getString('chartscreen','glucose_high'));
			SpikeANE.setUserDefaultsData("low", ModelLocator.resourceManagerInstance.getString('chartscreen','glucose_low'));
			SpikeANE.setUserDefaultsData("IOBString", ModelLocator.resourceManagerInstance.getString('treatments','iob_label'));
			SpikeANE.setUserDefaultsData("COBString", ModelLocator.resourceManagerInstance.getString('treatments','cob_label'));
			
			initialGraphDataSet = true;
		}
		
		private static function processChartGlucoseValues():void
		{
			activeGlucoseReadingsList = removeDuplicates(activeGlucoseReadingsList);
			if (activeGlucoseReadingsList.length == 0) return;
			
			activeGlucoseReadingsList.sortOn(["timestamp"], Array.NUMERIC);
			
			var currentTimestamp:Number
			if (BlueToothDevice.isFollower())
				currentTimestamp = (activeGlucoseReadingsList[0] as Object).timestamp;
			else
				currentTimestamp = activeGlucoseReadingsList[0].timestamp;
			var now:Number = new Date().valueOf();
			
			while (now - currentTimestamp > widgetHistory) 
			{
				activeGlucoseReadingsList.shift();
				if (activeGlucoseReadingsList.length > 0)
					currentTimestamp = activeGlucoseReadingsList[0].timestamp;
				else
					break;
			}
			
			var maxReadings:int = historyTimespan * 12;
			if (activeGlucoseReadingsList.length > maxReadings)
			{
				while (activeGlucoseReadingsList.length > maxReadings) 
				{
					activeGlucoseReadingsList.shift();
				}
			}
		}
		
		private static function removeDuplicates(array:Array):Array
		{
			var dict:Dictionary = new Dictionary();
			
			for (var i:int = array.length-1; i>=0; --i)
			{
				var timestamp:String = String((array[i] as Object).timestamp);
				if (!dict[timestamp])
					dict[timestamp] = true;
				else
					array.splice(i,1);
			}
			
			dict = null;
			
			return array;
		}
		
		private static function updateTreatments():void
		{
			Trace.myTrace("WidgetService.as", "Sending updated IOB and COB values to widget!");
			
			var now:Number = new Date().valueOf();
			
			SpikeANE.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			SpikeANE.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
		}
		
		private static function onTreatmentRefresh(e:Event):void
		{
			updateTreatments();
		}
		
		private static function isLowValue(value:String):Boolean
		{
			var returnValue:Boolean = false;
			
			if (
				value == "LOW" ||
				value == "??0" ||
				value == "?SN" ||
				value == "??2" ||
				value == "?NA" ||
				value == "?NC" ||
				value == "?CD" ||
				value == "?AD" ||
				value == "?RF" ||
				value == "???"
			)
			{
				returnValue = true;
			}
			
			return returnValue;
		}
		
		private static function onBloodGlucoseReceived(e:Event):void
		{
			if (!initialGraphDataSet) //Compatibility with follower mode because we get a new glucose event before Spike sends the initial chart data.
				setInitialGraphData();
			
			Trace.myTrace("WidgetService.as", "Sending new glucose reading to widget!");
			
			var currentReading:BgReading;
			if (!BlueToothDevice.isFollower())
				currentReading = BgReading.lastNoSensor();
			else
				currentReading = BgReading.lastWithCalculatedValue();
			
			if ((Calibration.allForSensor().length < 2 && !BlueToothDevice.isFollower()) || currentReading == null || currentReading.calculatedValue == 0 || (currentReading.calibration == null && !BlueToothDevice.isFollower()))
				return;
			
			var latestGlucose:String = BgGraphBuilder.unitizedString(currentReading.calculatedValue, CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true");
			var latestGlucoseValue:Number = Number(latestGlucose);
			if (CommonSettings.getCommonSetting(CommonSettings.COMMON_SETTING_DO_MGDL) == "true")
			{
				if (isLowValue(latestGlucose) || latestGlucoseValue < 40)
					latestGlucoseValue = 38;
				else if (latestGlucose == "HIGH" || latestGlucoseValue > 400)
					latestGlucoseValue = 400;
			}
			else
			{
				var lowestPossibleValue:Number = Math.round(((BgReading.mgdlToMmol((40))) * 10)) / 10;
				var highestPossibleValue:Number = Math.round(((BgReading.mgdlToMmol((400))) * 10)) / 10
				if (isLowValue(latestGlucose) || latestGlucoseValue < lowestPossibleValue)
					latestGlucoseValue = lowestPossibleValue;
				else if (latestGlucose == "HIGH" || latestGlucoseValue > highestPossibleValue)
					latestGlucoseValue = highestPossibleValue;
			}
			
			activeGlucoseReadingsList.push( { value: latestGlucoseValue, time: getGlucoseTimeFormatted(currentReading.timestamp, true), timestamp: currentReading.timestamp } ); 
			processChartGlucoseValues();
			
			var now:Number = new Date().valueOf();
			
			//Save data to User Defaults
			SpikeANE.setUserDefaultsData("latestWidgetUpdate", ModelLocator.resourceManagerInstance.getString('widgetservice','last_update_label') + " " + getLastUpdate(currentReading.timestamp) + ", " + getGlucoseTimeFormatted(currentReading.timestamp, false));
			SpikeANE.setUserDefaultsData("latestGlucoseValue", latestGlucose);
			SpikeANE.setUserDefaultsData("latestGlucoseSlopeArrow", currentReading.slopeArrow());
			SpikeANE.setUserDefaultsData("latestGlucoseDelta", MathHelper.formatNumberToStringWithPrefix(Number(BgGraphBuilder.unitizedDeltaString(false, true))));
			SpikeANE.setUserDefaultsData("latestGlucoseTime", String(currentReading.timestamp));
			SpikeANE.setUserDefaultsData("chartData", SpikeJSON.stringify(activeGlucoseReadingsList));
			SpikeANE.setUserDefaultsData("IOB", GlucoseFactory.formatIOB(TreatmentsManager.getTotalIOB(now)));
			SpikeANE.setUserDefaultsData("COB", GlucoseFactory.formatCOB(TreatmentsManager.getTotalCOB(now)));
		}
		
		/**
		 * Utility
		 */
		private static function getLastUpdate(timestamp:Number):String
		{
			var glucoseDate:Date = new Date(timestamp);
			
			return StringUtil.trim(months[glucoseDate.month]) + " " + glucoseDate.date;
		}
		
		private static function getGlucoseTimeFormatted(timestamp:Number, formatForChartLabel:Boolean):String
		{
			var glucoseDate:Date = new Date(timestamp);
			var timeFormatted:String;
			
			if (dateFormat == null || dateFormat.slice(0,2) == "24")
			{
				if (formatForChartLabel)
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_24H, widgetHistory == TIME_2_HOURS || DeviceInfo.isSmallScreenDevice());
				else
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_24H);
			}
			else
			{
				if (formatForChartLabel)
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_12H, widgetHistory == TIME_2_HOURS  || DeviceInfo.isSmallScreenDevice(), widgetHistory == TIME_1_HOUR && !DeviceInfo.isSmallScreenDevice());
				else
					timeFormatted = TimeSpan.formatHoursMinutes(glucoseDate.getHours(), glucoseDate.getMinutes(), TimeSpan.TIME_FORMAT_12H);
			}
			
			return timeFormatted;
		}
	}
}