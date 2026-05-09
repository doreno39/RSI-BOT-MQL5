//+------------------------------------------------------------------+
//|                                             RSI_LongShort.mq5    |
//|                       RSI Long/Short Indicator                   |
//|  Port từ chiến lược TradingView — dùng thư viện RSISignal.mqh   |
//+------------------------------------------------------------------+
#property copyright   "rsi-bot"
#property version     "1.00"
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_plots   7

//---- Plot 0: RSI Mid (tím)
#property indicator_label1  "RSI"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrMediumOrchid
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//---- Plot 1: EMA9 (cam)
#property indicator_label2  "EMA9"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//---- Plot 2: WMA45 (xanh lá đậm)
#property indicator_label3  "WMA45"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrForestGreen
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//---- Plot 3: Buy Arrow (xanh lá, mũi tên lên)
#property indicator_label4  "Buy"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_style4  STYLE_SOLID
#property indicator_width4  2

//---- Plot 4: Sell Arrow (đỏ, mũi tên xuống)
#property indicator_label5  "Sell"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

//---- Plot 5: RSI High — overbought (đỏ)
#property indicator_label6  "RSI_High"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrRed
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

//---- Plot 6: RSI Low — oversold (xanh lá)
#property indicator_label7  "RSI_Low"
#property indicator_type7   DRAW_LINE
#property indicator_color7  clrLime
#property indicator_style7  STYLE_SOLID
#property indicator_width7  1

#include <RSISignal.mqh>

//--- Input parameters
input int    RSI_Period         = 14;
input int    EMA_Period         = 9;
input int    WMA_Period         = 45;
input int    Falling_Length     = 3;
input int    Expansion_Length   = 5;
input double Distance_Threshold = 10.0;
input double Overbought         = 80.0;
input double Oversold           = 20.0;
input int    PrevTrend_Lookback = 50;
input string TelegramBotToken   = "";
input string TelegramChatId     = "";
input bool   EnableTelegram     = false;

//--- Indicator buffers
double RSIMidBuffer[];   // Buffer 0 — RSI trung gian (tím)
double EMA9Buffer[];     // Buffer 1 — EMA9 (cam)
double WMA45Buffer[];    // Buffer 2 — WMA45 (xanh đậm)
double BuyBuffer[];      // Buffer 3 — Mũi tên Buy
double SellBuffer[];     // Buffer 4 — Mũi tên Sell
double RSIHighBuffer[];  // Buffer 5 — RSI vùng overbought (đỏ)
double RSILowBuffer[];   // Buffer 6 — RSI vùng oversold (xanh lá)

//--- RSI indicator handle
int rsiHandle = INVALID_HANDLE;

//--- Pre-computed expand arrays (persistent, rebuilt mỗi OnCalculate)
bool downExpandArr[];
bool upExpandArr[];

//--- Alert state (tránh spam)
int      last_alert_bar  = -1;

//+------------------------------------------------------------------+
//| Helper: chuyển ENUM_TIMEFRAMES thành chuỗi                      |
//+------------------------------------------------------------------+
string GetTFString(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "?";
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Khởi tạo RSI handle
   rsiHandle = iRSI(NULL, 0, RSI_Period, PRICE_CLOSE);
   if(rsiHandle == INVALID_HANDLE)
     {
      Print("RSI_LongShort: Không thể tạo RSI handle!");
      return INIT_FAILED;
     }

   //--- Liên kết buffers
   SetIndexBuffer(0, RSIMidBuffer,  INDICATOR_DATA);
   SetIndexBuffer(1, EMA9Buffer,    INDICATOR_DATA);
   SetIndexBuffer(2, WMA45Buffer,   INDICATOR_DATA);
   SetIndexBuffer(3, BuyBuffer,     INDICATOR_DATA);
   SetIndexBuffer(4, SellBuffer,    INDICATOR_DATA);
   SetIndexBuffer(5, RSIHighBuffer, INDICATOR_DATA);
   SetIndexBuffer(6, RSILowBuffer,  INDICATOR_DATA);

   //--- Đánh dấu AS_SERIES cho buffers (index 0 = bar hiện tại)
   //    Phải khớp với rsiRaw/ema9Arr/wma45Arr dùng trong OnCalculate
   ArraySetAsSeries(RSIMidBuffer,  true);
   ArraySetAsSeries(EMA9Buffer,    true);
   ArraySetAsSeries(WMA45Buffer,   true);
   ArraySetAsSeries(BuyBuffer,     true);
   ArraySetAsSeries(SellBuffer,    true);
   ArraySetAsSeries(RSIHighBuffer, true);
   ArraySetAsSeries(RSILowBuffer,  true);

   //--- Giá trị rỗng mặc định
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(6, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Arrow codes
   PlotIndexSetInteger(3, PLOT_ARROW, 233); // Mũi tên lên
   PlotIndexSetInteger(4, PLOT_ARROW, 234); // Mũi tên xuống

   //--- Arrow shift (dịch chỉnh vị trí visual)
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, 0);
   PlotIndexSetInteger(4, PLOT_ARROW_SHIFT, 0);

   //--- Horizontal level lines
   IndicatorSetInteger(INDICATOR_LEVELS, 3);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 0, Overbought);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 1, 50.0);
   IndicatorSetDouble(INDICATOR_LEVELVALUE, 2, Oversold);

   //--- Tên indicator
   IndicatorSetString(INDICATOR_SHORTNAME, "RSI Long/Short");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(rsiHandle != INVALID_HANDLE)
     {
      IndicatorRelease(rsiHandle);
      rsiHandle = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &volume[],
                const long &tick_volume[],
                const int &spread[])
  {
   //--- Cần ít nhất RSI_Period + WMA_Period bars
   int minBars = RSI_Period + WMA_Period + Falling_Length + Expansion_Length + 5;
   if(rates_total < minBars)
      return 0;

   if(rsiHandle == INVALID_HANDLE)
      return 0;

   //------------------------------------------------------------------
   // Bước 1: Copy RSI từ built-in handle
   //------------------------------------------------------------------
   double rsiRaw[];
   ArraySetAsSeries(rsiRaw, true);

   if(CopyBuffer(rsiHandle, 0, 0, rates_total, rsiRaw) < rates_total)
     {
      // Dữ liệu chưa sẵn sàng, thử lại tick tiếp theo
      return prev_calculated;
     }

   //------------------------------------------------------------------
   // Bước 2: Tính EMA9 và WMA45 của RSI
   // Dùng mảng AS_SERIES (index 0 = bar mới nhất) nhất quán với rsiRaw
   //------------------------------------------------------------------
   double ema9Arr[];
   double wma45Arr[];
   ArrayResize(ema9Arr,  rates_total);
   ArrayResize(wma45Arr, rates_total);
   // Đánh dấu AS_SERIES TRƯỚC khi ghi, để index nhất quán với rsiRaw
   ArraySetAsSeries(ema9Arr,  true);
   ArraySetAsSeries(wma45Arr, true);

   // Khởi tạo tất cả về EMPTY_VALUE
   ArrayInitialize(ema9Arr,  EMPTY_VALUE);
   ArrayInitialize(wma45Arr, EMPTY_VALUE);

   // ---- Tính EMA9 một lần duy nhất (O(N)) ----
   // Mảng AS_SERIES: index 0 = bar mới nhất, index rates_total-1 = bar cũ nhất
   // Seed EMA bằng SMA của EMA_Period bars cũ nhất
   int seedStart = rates_total - EMA_Period;
   if(seedStart >= 0)
     {
      double emaSeed = 0.0;
      for(int i = seedStart; i < rates_total; i++)
         emaSeed += rsiRaw[i];
      emaSeed /= EMA_Period;

      double alphaEMA = 2.0 / (EMA_Period + 1.0);
      ema9Arr[rates_total - EMA_Period] = emaSeed;
      // Chạy EMA từ bar cũ về bar mới (index cao → thấp trong AS_SERIES)
      for(int i = rates_total - EMA_Period - 1; i >= 0; i--)
         ema9Arr[i] = alphaEMA * rsiRaw[i] + (1.0 - alphaEMA) * ema9Arr[i + 1];
     }

   // ---- Tính WMA45 — O(N × period) với period cố định = O(N) ----
   for(int i = 0; i < rates_total; i++)
      wma45Arr[i] = CalcWMA(rsiRaw, WMA_Period, i);

   //------------------------------------------------------------------
   // Bước 3: Pre-compute expand arrays một lần duy nhất trước loop
   //------------------------------------------------------------------
   CalcExpandArrays(rsiRaw, ema9Arr, wma45Arr,
                    downExpandArr, upExpandArr,
                    rates_total, Falling_Length, Expansion_Length);

   //------------------------------------------------------------------
   // Bước 4: Tính tín hiệu và điền buffer
   //------------------------------------------------------------------
   // Lần đầu (prev_calculated == 0): tính toàn bộ history
   // Các lần sau: chỉ tính lại các bar mới + bar 1 (anti-repaint)
   int loopEnd;
   if(prev_calculated == 0)
     {
      // Reset toàn bộ buffer
      ArrayInitialize(RSIMidBuffer,  EMPTY_VALUE);
      ArrayInitialize(EMA9Buffer,    EMPTY_VALUE);
      ArrayInitialize(WMA45Buffer,   EMPTY_VALUE);
      ArrayInitialize(BuyBuffer,     EMPTY_VALUE);
      ArrayInitialize(SellBuffer,    EMPTY_VALUE);
      ArrayInitialize(RSIHighBuffer, EMPTY_VALUE);
      ArrayInitialize(RSILowBuffer,  EMPTY_VALUE);
      loopEnd = rates_total;
     }
   else
     {
      // Tính lại các bar mới thêm + bar 1 (bar 0 = forming, bar 1 = closed)
      int newBars = rates_total - prev_calculated;
      loopEnd = newBars + 2; // +2: bar 0 (current) và bar 1 (vừa đóng)
      if(loopEnd > rates_total)
         loopEnd = rates_total;
     }

   for(int i = 0; i < loopEnd; i++)
     {
      // Bỏ qua nếu không đủ dữ liệu EMA/WMA
      if(ema9Arr[i] == EMPTY_VALUE || wma45Arr[i] == EMPTY_VALUE)
         continue;

      double rsiVal  = rsiRaw[i];
      double ema9Val = ema9Arr[i];
      double wmaVal  = wma45Arr[i];

      //--- Điền EMA9 và WMA45 (index buffer theo AS_SERIES: 0=mới nhất)
      // Buffer của indicator là non-series (index 0 = bar CŨ nhất trong array)
      // Nhưng khi dùng SetIndexBuffer, MT5 tự quản lý — index i ở đây
      // tương ứng với bar cách hiện tại i bars (0 = bar hiện tại)
      EMA9Buffer[i]    = ema9Val;
      WMA45Buffer[i]   = wmaVal;

      //--- Phân phối RSI vào 3 buffers theo ngưỡng
      RSIMidBuffer[i]  = EMPTY_VALUE;
      RSIHighBuffer[i] = EMPTY_VALUE;
      RSILowBuffer[i]  = EMPTY_VALUE;

      if(rsiVal >= Overbought)
         RSIHighBuffer[i] = rsiVal;
      else if(rsiVal <= Oversold)
         RSILowBuffer[i] = rsiVal;
      else
         RSIMidBuffer[i] = rsiVal;

      //--- Tính tín hiệu (dùng pre-computed expand arrays)
      RSISignalResult sig = CalcRSISignalFast(
                               rsiRaw, ema9Arr, wma45Arr,
                               downExpandArr, upExpandArr,
                               i,
                               Distance_Threshold,
                               PrevTrend_Lookback
                            );

      //--- Điền arrow buffers
      if(sig.isBuy)
         BuyBuffer[i]  = rsiVal - 8.0;
      else
         BuyBuffer[i]  = EMPTY_VALUE;

      if(sig.isSell)
         SellBuffer[i] = rsiVal + 8.0;
      else
         SellBuffer[i] = EMPTY_VALUE;
     }

   //------------------------------------------------------------------
   // Bước 4: Telegram alert — chỉ khi có bar mới
   //------------------------------------------------------------------
   if(rates_total > prev_calculated && last_alert_bar != rates_total)
     {
      // Kiểm tra tín hiệu tại bar 1 (bar vừa đóng, không còn thay đổi)
      if(rates_total >= 2 && ema9Arr[1] != EMPTY_VALUE && wma45Arr[1] != EMPTY_VALUE)
        {
         RSISignalResult sig1 = CalcRSISignalFast(
                                   rsiRaw, ema9Arr, wma45Arr,
                                   downExpandArr, upExpandArr,
                                   1,
                                   Distance_Threshold,
                                   PrevTrend_Lookback
                                );

         if(sig1.isBuy || sig1.isSell)
           {
            last_alert_bar = rates_total;

            if(EnableTelegram && TelegramBotToken != "" && TelegramChatId != "")
              {
               string direction = sig1.isBuy ? "BUY" : "SELL";
               string emoji     = sig1.isBuy ? "📈" : "📉";
               string msg = emoji + " " + direction + " Signal\n"
                          + "Symbol: " + Symbol() + " | TF: " + GetTFString(Period()) + "\n"
                          + "RSI: "   + DoubleToString(sig1.rsi,  2)
                          + " | EMA9: " + DoubleToString(sig1.ema9, 2)
                          + " | WMA45: " + DoubleToString(sig1.wma45, 2) + "\n"
                          + "Price: " + DoubleToString(close[1], _Digits) + "\n"
                          + "Time: "  + TimeToString(time[1], TIME_DATE | TIME_MINUTES);
               bool sent = SendTelegramMessage(TelegramBotToken, TelegramChatId, msg);
               if(!sent)
                  Print("RSI_LongShort: Telegram alert failed. Check token, chat_id, and WebRequest whitelist.");
              }
           }
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
