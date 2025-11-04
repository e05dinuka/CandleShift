//+------------------------------------------------------------------+
//|                                         DynamicCandleShift.mq5   |
//|                                  Copyright 2025, CandleShift     |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, CandleShift"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   1

//--- Plot settings
#property indicator_label1  "Shifted Candles"
#property indicator_type1   DRAW_CANDLES
#property indicator_color1  clrDodgerBlue,clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- Input parameters
input int      CandlePeriod = 15;         // Candle Period in Minutes
input int      InitialShift = 0;          // Initial Time Shift (minutes)
input color    ButtonColorLeft = clrGreen; // Left Button Color
input color    ButtonColorRight = clrGreen;// Right Button Color
input int      ButtonWidth = 80;           // Button Width
input int      ButtonHeight = 30;          // Button Height
input int      ButtonX = 20;               // Buttons X Position
input int      ButtonY = 50;               // Buttons Y Position

//--- Indicator buffers
double OpenBuffer[];
double HighBuffer[];
double LowBuffer[];
double CloseBuffer[];

//--- Global variables
int    g_shift = 0;              // Current shift in minutes
string g_buttonLeft = "";        // Left button name
string g_buttonRight = "";       // Right button name
string g_labelInfo = "";         // Info label name
datetime g_lastBarTime = 0;      // Last processed bar time

//--- Structure for candle data
struct CandleData
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     volume;
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set initial shift
   g_shift = InitialShift;

   //--- Initialize indicator buffers
   SetIndexBuffer(0, OpenBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, HighBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, LowBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, CloseBuffer, INDICATOR_DATA);

   //--- Set drawing parameters
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, CandlePeriod);

   //--- Set empty value
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

   //--- Set indicator name
   string shortName = StringFormat("DynamicCandleShift(%d min, shift: %d)",
                                   CandlePeriod, g_shift);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);

   //--- Create control buttons
   CreateButtons();

   //--- Update info label
   UpdateInfoLabel();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete all objects created by indicator
   DeleteButtons();
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Check if we have enough data
   if(rates_total < CandlePeriod)
      return(0);

   //--- Set array as series
   ArraySetAsSeries(OpenBuffer, true);
   ArraySetAsSeries(HighBuffer, true);
   ArraySetAsSeries(LowBuffer, true);
   ArraySetAsSeries(CloseBuffer, true);

   //--- Get 1-minute data
   MqlRates m1_rates[];
   ArraySetAsSeries(m1_rates, true);

   int copied = CopyRates(_Symbol, PERIOD_M1, 0, rates_total * CandlePeriod, m1_rates);

   if(copied <= 0)
   {
      Print("Error copying M1 rates: ", GetLastError());
      return(0);
   }

   //--- Calculate shifted candles
   int calculated_bars = CalculateShiftedCandles(m1_rates, copied);

   //--- Update info label on new bar
   datetime currentBarTime = iTime(_Symbol, PERIOD_M1, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      UpdateInfoLabel();
   }

   //--- Return value of prev_calculated for next call
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate shifted candles from M1 data                           |
//+------------------------------------------------------------------+
int CalculateShiftedCandles(const MqlRates &m1_rates[], int total)
{
   if(total <= 0)
      return(0);

   //--- Initialize all buffers with empty values
   ArrayInitialize(OpenBuffer, 0.0);
   ArrayInitialize(HighBuffer, 0.0);
   ArrayInitialize(LowBuffer, 0.0);
   ArrayInitialize(CloseBuffer, 0.0);

   //--- Get the base time of the latest candle
   datetime currentTime = m1_rates[0].time;

   //--- Calculate the shifted start time for the current candle
   datetime shiftedStartTime = GetShiftedCandleStartTime(currentTime, CandlePeriod, g_shift);

   //--- Temporary storage for candles being built
   CandleData currentCandle;
   bool candleStarted = false;
   int candleIndex = 0;

   //--- Process M1 bars from oldest to newest
   for(int i = total - 1; i >= 0; i--)
   {
      datetime barTime = m1_rates[i].time;
      datetime barCandleStart = GetShiftedCandleStartTime(barTime, CandlePeriod, g_shift);

      //--- Check if this bar belongs to a new candle
      if(!candleStarted || barCandleStart != currentCandle.time)
      {
         //--- Save previous candle if it was started
         if(candleStarted)
         {
            SaveCandle(currentCandle, candleIndex);
            candleIndex++;
         }

         //--- Start new candle
         currentCandle.time = barCandleStart;
         currentCandle.open = m1_rates[i].open;
         currentCandle.high = m1_rates[i].high;
         currentCandle.low = m1_rates[i].low;
         currentCandle.close = m1_rates[i].close;
         currentCandle.volume = m1_rates[i].tick_volume;
         candleStarted = true;
      }
      else
      {
         //--- Update current candle
         currentCandle.high = MathMax(currentCandle.high, m1_rates[i].high);
         currentCandle.low = MathMin(currentCandle.low, m1_rates[i].low);
         currentCandle.close = m1_rates[i].close;
         currentCandle.volume += m1_rates[i].tick_volume;
      }
   }

   //--- Save the last candle
   if(candleStarted)
   {
      SaveCandle(currentCandle, candleIndex);
      candleIndex++;
   }

   return(candleIndex);
}

//+------------------------------------------------------------------+
//| Get shifted candle start time                                    |
//+------------------------------------------------------------------+
datetime GetShiftedCandleStartTime(datetime barTime, int period, int shift)
{
   MqlDateTime dt;
   TimeToStruct(barTime, dt);

   //--- Calculate total minutes from start of day
   int totalMinutes = dt.hour * 60 + dt.min;

   //--- Apply shift
   totalMinutes += shift;

   //--- Handle negative values (previous day)
   while(totalMinutes < 0)
      totalMinutes += 1440; // 24 hours * 60 minutes

   //--- Calculate which candle period this belongs to
   int candleNumber = totalMinutes / period;

   //--- Calculate the start time of this candle
   int startMinutes = candleNumber * period - shift;

   //--- Handle day boundaries
   if(startMinutes < 0)
   {
      startMinutes += 1440;
      dt.day--;
   }
   else if(startMinutes >= 1440)
   {
      startMinutes -= 1440;
      dt.day++;
   }

   //--- Set the calculated time
   dt.hour = startMinutes / 60;
   dt.min = startMinutes % 60;
   dt.sec = 0;

   return(StructToTime(dt));
}

//+------------------------------------------------------------------+
//| Save candle to buffers                                           |
//+------------------------------------------------------------------+
void SaveCandle(const CandleData &candle, int index)
{
   if(index < 0 || index >= ArraySize(OpenBuffer))
      return;

   //--- Reverse index for series arrays
   int bufferIndex = ArraySize(OpenBuffer) - 1 - index;

   if(bufferIndex >= 0 && bufferIndex < ArraySize(OpenBuffer))
   {
      OpenBuffer[bufferIndex] = candle.open;
      HighBuffer[bufferIndex] = candle.high;
      LowBuffer[bufferIndex] = candle.low;
      CloseBuffer[bufferIndex] = candle.close;
   }
}

//+------------------------------------------------------------------+
//| Create control buttons                                           |
//+------------------------------------------------------------------+
void CreateButtons()
{
   long chartId = ChartID();

   //--- Create unique names
   g_buttonLeft = "DCS_ButtonLeft_" + IntegerToString(chartId);
   g_buttonRight = "DCS_ButtonRight_" + IntegerToString(chartId);
   g_labelInfo = "DCS_InfoLabel_" + IntegerToString(chartId);

   //--- Create LEFT button
   if(!ObjectCreate(chartId, g_buttonLeft, OBJ_BUTTON, 0, 0, 0))
   {
      Print("Error creating left button: ", GetLastError());
   }
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_XDISTANCE, ButtonX);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_YDISTANCE, ButtonY);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_XSIZE, ButtonWidth);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_YSIZE, ButtonHeight);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_BGCOLOR, ButtonColorLeft);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_COLOR, clrWhite);
   ObjectSetString(chartId, g_buttonLeft, OBJPROP_TEXT, "◄ LEFT");
   ObjectSetString(chartId, g_buttonLeft, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(chartId, g_buttonLeft, OBJPROP_SELECTABLE, false);

   //--- Create RIGHT button
   if(!ObjectCreate(chartId, g_buttonRight, OBJ_BUTTON, 0, 0, 0))
   {
      Print("Error creating right button: ", GetLastError());
   }
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_XDISTANCE, ButtonX + ButtonWidth + 10);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_YDISTANCE, ButtonY);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_XSIZE, ButtonWidth);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_YSIZE, ButtonHeight);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_BGCOLOR, ButtonColorRight);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_COLOR, clrWhite);
   ObjectSetString(chartId, g_buttonRight, OBJPROP_TEXT, "RIGHT ►");
   ObjectSetString(chartId, g_buttonRight, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(chartId, g_buttonRight, OBJPROP_SELECTABLE, false);

   //--- Create info label
   if(!ObjectCreate(chartId, g_labelInfo, OBJ_LABEL, 0, 0, 0))
   {
      Print("Error creating info label: ", GetLastError());
   }
   ObjectSetInteger(chartId, g_labelInfo, OBJPROP_XDISTANCE, ButtonX);
   ObjectSetInteger(chartId, g_labelInfo, OBJPROP_YDISTANCE, ButtonY - 30);
   ObjectSetInteger(chartId, g_labelInfo, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(chartId, g_labelInfo, OBJPROP_COLOR, clrWhite);
   ObjectSetString(chartId, g_labelInfo, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(chartId, g_labelInfo, OBJPROP_FONTSIZE, 10);

   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
//| Delete control buttons                                           |
//+------------------------------------------------------------------+
void DeleteButtons()
{
   long chartId = ChartID();

   ObjectDelete(chartId, g_buttonLeft);
   ObjectDelete(chartId, g_buttonRight);
   ObjectDelete(chartId, g_labelInfo);

   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
//| Update info label                                                |
//+------------------------------------------------------------------+
void UpdateInfoLabel()
{
   long chartId = ChartID();

   //--- Calculate example candle times
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);

   //--- Set to current hour and minute 0
   dt.min = 0;
   dt.sec = 0;
   datetime baseTime = StructToTime(dt);

   //--- Calculate first three candle start times
   string times = "";
   for(int i = 0; i < 3; i++)
   {
      datetime candleTime = baseTime + (i * CandlePeriod * 60) + (g_shift * 60);
      TimeToStruct(candleTime, dt);
      times += StringFormat("%02d:%02d", dt.hour, dt.min);
      if(i < 2)
         times += ", ";
   }

   string info = StringFormat("Shift: %d min | Period: %d min | Times: %s...",
                             g_shift, CandlePeriod, times);

   ObjectSetString(chartId, g_labelInfo, OBJPROP_TEXT, info);
   ChartRedraw(chartId);
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- Handle button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == g_buttonLeft)
      {
         //--- Shift left (decrease shift value)
         g_shift--;
         Print("Shift decreased to: ", g_shift);

         //--- Reset button state
         ObjectSetInteger(ChartID(), g_buttonLeft, OBJPROP_STATE, false);

         //--- Update indicator
         UpdateIndicator();
      }
      else if(sparam == g_buttonRight)
      {
         //--- Shift right (increase shift value)
         g_shift++;
         Print("Shift increased to: ", g_shift);

         //--- Reset button state
         ObjectSetInteger(ChartID(), g_buttonRight, OBJPROP_STATE, false);

         //--- Update indicator
         UpdateIndicator();
      }
   }
}

//+------------------------------------------------------------------+
//| Update indicator after shift change                              |
//+------------------------------------------------------------------+
void UpdateIndicator()
{
   //--- Update short name
   string shortName = StringFormat("DynamicCandleShift(%d min, shift: %d)",
                                   CandlePeriod, g_shift);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);

   //--- Update info label
   UpdateInfoLabel();

   //--- Force recalculation
   ChartRedraw(ChartID());

   //--- Trigger indicator recalculation by refreshing the chart
   EventChartCustom(ChartID(), 1, 0, 0.0, "Shift Updated");
}
//+------------------------------------------------------------------+
