//+------------------------------------------------------------------+
//|                                                   RSISignal.mqh  |
//|                 RSI Long/Short Strategy Signal Library           |
//|  Pure header — no OnInit/OnCalculate/global state               |
//+------------------------------------------------------------------+
#ifndef RSISIGNAL_MQH
#define RSISIGNAL_MQH

#property copyright "rsi-bot"

//+------------------------------------------------------------------+
//| Result struct                                                    |
//+------------------------------------------------------------------+
struct RSISignalResult
  {
   double rsi;
   double ema9;
   double wma45;
   bool   isBuy;
   bool   isSell;
  };

//+------------------------------------------------------------------+
//| CalcWMA                                                          |
//| Tính WMA(period) tại vị trí idx trong mảng AS_SERIES            |
//| Bar gần nhất (idx) nhận trọng số cao nhất (= period)            |
//| Bar cũ hơn nhận trọng số thấp hơn                               |
//| Trả về EMPTY_VALUE nếu không đủ dữ liệu                         |
//+------------------------------------------------------------------+
double CalcWMA(const double &src[], int period, int idx)
  {
   if(period <= 0 || idx < 0)
      return EMPTY_VALUE;

   // Cần các bar từ idx đến idx+period-1
   int lastNeeded = idx + period - 1;
   if(lastNeeded >= ArraySize(src))
      return EMPTY_VALUE;

   double weightedSum = 0.0;
   double weightSum   = 0.0;

   // src[idx]         = bar mới nhất  -> weight = period
   // src[idx+1]       = bar cũ hơn 1  -> weight = period-1
   // ...
   // src[idx+period-1]= bar cũ nhất   -> weight = 1
   for(int j = 0; j < period; j++)
     {
      double w = (double)(period - j);
      weightedSum += src[idx + j] * w;
      weightSum   += w;
     }

   return weightedSum / weightSum;
  }

//+------------------------------------------------------------------+
//| IsFalling                                                        |
//| Trả về true nếu src giảm dần từ hiện tại về quá khứ:           |
//|   src[idx] < src[idx+1] < ... < src[idx+length-1]               |
//+------------------------------------------------------------------+
bool IsFalling(const double &src[], int idx, int length)
  {
   if(length <= 1)
      return true;

   int lastNeeded = idx + length - 1;
   if(idx < 0 || lastNeeded >= ArraySize(src))
      return false;

   for(int i = idx; i < idx + length - 1; i++)
     {
      if(src[i] >= src[i + 1])
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| IsRising                                                         |
//| Trả về true nếu src tăng dần từ hiện tại về quá khứ:           |
//|   src[idx] > src[idx+1] > ... > src[idx+length-1]               |
//+------------------------------------------------------------------+
bool IsRising(const double &src[], int idx, int length)
  {
   if(length <= 1)
      return true;

   int lastNeeded = idx + length - 1;
   if(idx < 0 || lastNeeded >= ArraySize(src))
      return false;

   for(int i = idx; i < idx + length - 1; i++)
     {
      if(src[i] <= src[i + 1])
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| HighestN                                                         |
//| Tìm giá trị lớn nhất trong src[idx], src[idx+1],..,            |
//| src[idx+length-1]                                               |
//+------------------------------------------------------------------+
double HighestN(const double &src[], int idx, int length)
  {
   if(length <= 0 || idx < 0)
      return EMPTY_VALUE;

   int lastNeeded = idx + length - 1;
   if(lastNeeded >= ArraySize(src))
      return EMPTY_VALUE;

   double maxVal = src[idx];
   for(int i = idx + 1; i <= lastNeeded; i++)
     {
      if(src[i] > maxVal)
         maxVal = src[i];
     }
   return maxVal;
  }

//+------------------------------------------------------------------+
//| FindPrevTrend                                                    |
//| Tìm trong maxLookback bars trước idx (idx+1 .. idx+maxLookback) |
//| có bar nào trendArr = true không.                               |
//| Tương đương ta.valuewhen trong Pine Script.                     |
//+------------------------------------------------------------------+
bool FindPrevTrend(const bool &trendArr[], int idx, int maxLookback)
  {
   int arrSize = ArraySize(trendArr);
   for(int i = 1; i <= maxLookback; i++)
     {
      int checkIdx = idx + i;
      if(checkIdx >= arrSize)
         break;
      if(trendArr[checkIdx])
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| CalcRSISignal                                                    |
//| Hàm chính tính tín hiệu Buy/Sell tại bar idx.                  |
//|                                                                  |
//| Params:                                                          |
//|   rsiArr, ema9Arr, wma45Arr  — mảng AS_SERIES đã tính sẵn      |
//|   idx           — bar hiện tại cần tính tín hiệu               |
//|   fallingLen    — số bar dùng cho IsFalling/IsRising            |
//|   expansionLen  — số bar dùng cho HighestN expansion check      |
//|   distThreshold — ngưỡng khoảng cách wma45-ema9                |
//+------------------------------------------------------------------+
RSISignalResult CalcRSISignal(
   const double &rsiArr[],
   const double &ema9Arr[],
   const double &wma45Arr[],
   int    idx,
   int    fallingLen,
   int    expansionLen,
   double distThreshold,
   int    prevTrendLookback = 50)
  {
   RSISignalResult result;
   result.rsi   = rsiArr[idx];
   result.ema9  = ema9Arr[idx];
   result.wma45 = wma45Arr[idx];
   result.isBuy  = false;
   result.isSell = false;

   int arrSize = ArraySize(rsiArr);
   // Cần ít nhất idx+1 cho bar trước đó, và đủ cho expansion check
   int minRequired = idx + MathMax(fallingLen, expansionLen) + 1;
   if(minRequired >= arrSize)
      return result;

   // ---- Tính mảng diff tạm thời cho expansion check ----
   // Kích thước cần: trendArrLen + expansionLen + 1
   // (vì loop trendArr sẽ gọi HighestN tại i+1 với i tối đa = trendArrLen-1)
   int lookback = prevTrendLookback;
   int trendArrLen_pre = idx + lookback + 1;
   if(trendArrLen_pre > arrSize)
      trendArrLen_pre = arrSize;

   int diffLen = trendArrLen_pre + expansionLen + 1;
   if(diffLen > arrSize)
      diffLen = arrSize;

   double diffDown[];  // wma45 - rsi  (dùng cho downtrend expansion)
   double diffUp[];    // rsi - wma45  (dùng cho uptrend expansion)
   ArrayResize(diffDown, diffLen);
   ArrayResize(diffUp,   diffLen);
   for(int i = 0; i < diffLen; i++)
     {
      diffDown[i] = wma45Arr[i] - rsiArr[i];
      diffUp[i]   = rsiArr[i]   - wma45Arr[i];
     }

   // ---- Downtrend expanding ----
   bool downtrend_cur    = (rsiArr[idx]   < ema9Arr[idx]   && ema9Arr[idx]   < wma45Arr[idx]);
   bool falling_rsi      = IsFalling(rsiArr,   idx, fallingLen);
   bool falling_ema9     = IsFalling(ema9Arr,  idx, fallingLen);
   bool falling_wma45    = IsFalling(wma45Arr, idx, fallingLen);

   double highDownCur  = HighestN(diffDown, idx,     expansionLen);
   double highDownPrev = HighestN(diffDown, idx + 1, expansionLen);
   bool expansion_down = (highDownCur  != EMPTY_VALUE &&
                          highDownPrev != EMPTY_VALUE &&
                          highDownCur  >  highDownPrev);

   bool is_downtrend_expanding = downtrend_cur && falling_rsi && falling_ema9
                                 && falling_wma45 && expansion_down;

   // ---- Uptrend expanding ----
   bool uptrend_cur     = (rsiArr[idx]   > ema9Arr[idx]   && ema9Arr[idx]   > wma45Arr[idx]);
   bool rising_rsi      = IsRising(rsiArr,   idx, fallingLen);
   bool rising_ema9     = IsRising(ema9Arr,  idx, fallingLen);
   bool rising_wma45    = IsRising(wma45Arr, idx, fallingLen);

   double highUpCur  = HighestN(diffUp, idx,     expansionLen);
   double highUpPrev = HighestN(diffUp, idx + 1, expansionLen);
   bool expansion_up = (highUpCur  != EMPTY_VALUE &&
                        highUpPrev != EMPTY_VALUE &&
                        highUpCur  >  highUpPrev);

   bool is_uptrend_expanding = uptrend_cur && rising_rsi && rising_ema9
                               && rising_wma45 && expansion_up;

   // ---- Xây trendArr tạm thời để dùng FindPrevTrend ----
   // Dùng lại lookback và trendArrLen đã tính ở trên
   int trendArrLen = trendArrLen_pre;

   bool localDownExp[];
   bool localUpExp[];
   ArrayResize(localDownExp, trendArrLen);
   ArrayResize(localUpExp,   trendArrLen);

   for(int i = 0; i < trendArrLen; i++)
     {
      // Tính downtrend expanding tại i
      bool dt_i   = (rsiArr[i] < ema9Arr[i] && ema9Arr[i] < wma45Arr[i]);
      bool fr_i   = IsFalling(rsiArr,   i, fallingLen);
      bool fe_i   = IsFalling(ema9Arr,  i, fallingLen);
      bool fw_i   = IsFalling(wma45Arr, i, fallingLen);

      double hDc = HighestN(diffDown, i,     expansionLen);
      double hDp = HighestN(diffDown, i + 1, expansionLen);
      bool ed_i  = (hDc != EMPTY_VALUE && hDp != EMPTY_VALUE && hDc > hDp);

      localDownExp[i] = dt_i && fr_i && fe_i && fw_i && ed_i;

      // Tính uptrend expanding tại i
      bool ut_i   = (rsiArr[i] > ema9Arr[i] && ema9Arr[i] > wma45Arr[i]);
      bool rr_i   = IsRising(rsiArr,   i, fallingLen);
      bool re_i   = IsRising(ema9Arr,  i, fallingLen);
      bool rw_i   = IsRising(wma45Arr, i, fallingLen);

      double hUc = HighestN(diffUp, i,     expansionLen);
      double hUp = HighestN(diffUp, i + 1, expansionLen);
      bool eu_i  = (hUc != EMPTY_VALUE && hUp != EMPTY_VALUE && hUc > hUp);

      localUpExp[i] = ut_i && rr_i && re_i && rw_i && eu_i;
     }

   // ---- Buy Signal ----
   // Cond 1: RSI crosses above EMA9
   bool crossUp = (rsiArr[idx]   >  ema9Arr[idx]   &&
                   rsiArr[idx+1] <= ema9Arr[idx+1]);
   // Cond 2: EMA9 curling in (distance to WMA45 shrinking)
   bool curlingIn = (MathAbs(wma45Arr[idx]   - ema9Arr[idx])   <
                     MathAbs(wma45Arr[idx+1] - ema9Arr[idx+1]));
   // Cond 3: Previous downtrend
   bool prevDowntrend = (rsiArr[idx+1]  < ema9Arr[idx+1] &&
                         ema9Arr[idx+1] < wma45Arr[idx+1]);
   // Cond 4: Previously had downtrend expanding
   bool hadDownExpand = FindPrevTrend(localDownExp, idx, lookback);
   // Cond 5: EMA9 slope >= 0
   bool ema9Up = (ema9Arr[idx] >= ema9Arr[idx+1]);
   // Cond 6: Distance OK
   bool distOK = (MathAbs(wma45Arr[idx] - ema9Arr[idx]) <= distThreshold);

   result.isBuy = crossUp && curlingIn && prevDowntrend
                  && hadDownExpand && ema9Up && distOK;

   // ---- Sell Signal ----
   // Cond 1: RSI crosses below EMA9
   bool crossDown = (rsiArr[idx]   <  ema9Arr[idx]   &&
                     rsiArr[idx+1] >= ema9Arr[idx+1]);
   // Cond 3: Previous uptrend
   bool prevUptrend = (rsiArr[idx+1]  > ema9Arr[idx+1] &&
                       ema9Arr[idx+1] > wma45Arr[idx+1]);
   // Cond 4: Previously had uptrend expanding
   bool hadUpExpand = FindPrevTrend(localUpExp, idx, lookback);
   // Cond 5: EMA9 slope <= 0
   bool ema9Down = (ema9Arr[idx] <= ema9Arr[idx+1]);
   // Cond 2 & 6 reuse same curlingIn and distOK

   result.isSell = crossDown && curlingIn && prevUptrend
                   && hadUpExpand && ema9Down && distOK;

   return result;
  }

//+------------------------------------------------------------------+
//| CalcExpandArrays                                                 |
//| Tính downExpandArr và upExpandArr cho toàn bộ bars              |
//| O(N × fallingLen + N × expansionLen) — gọi một lần trước loop  |
//+------------------------------------------------------------------+
void CalcExpandArrays(
   const double &rsiArr[],
   const double &ema9Arr[],
   const double &wma45Arr[],
   bool         &outDown[],   // output: downtrend expanding
   bool         &outUp[],     // output: uptrend expanding
   int    totalBars,
   int    fallingLen,
   int    expansionLen)
  {
   ArrayResize(outDown, totalBars);
   ArrayResize(outUp,   totalBars);

   // Pre-compute diff arrays (O(N))
   double diffDown[];
   double diffUp[];
   ArrayResize(diffDown, totalBars);
   ArrayResize(diffUp,   totalBars);
   for(int i = 0; i < totalBars; i++)
     {
      diffDown[i] = wma45Arr[i] - rsiArr[i];
      diffUp[i]   = rsiArr[i]   - wma45Arr[i];
     }

   // Compute expand arrays (O(N × expansionLen))
   for(int i = 0; i < totalBars; i++)
     {
      outDown[i] = false;
      outUp[i]   = false;

      bool dt = rsiArr[i] < ema9Arr[i] && ema9Arr[i] < wma45Arr[i];
      bool ut = rsiArr[i] > ema9Arr[i] && ema9Arr[i] > wma45Arr[i];

      if(dt)
        {
         bool fr = IsFalling(rsiArr,   i, fallingLen);
         bool fe = IsFalling(ema9Arr,  i, fallingLen);
         bool fw = IsFalling(wma45Arr, i, fallingLen);
         double hDc = HighestN(diffDown, i,     expansionLen);
         double hDp = HighestN(diffDown, i + 1, expansionLen);
         bool ed = hDc != EMPTY_VALUE && hDp != EMPTY_VALUE && hDc > hDp;
         outDown[i] = fr && fe && fw && ed;
        }

      if(ut)
        {
         bool rr = IsRising(rsiArr,   i, fallingLen);
         bool re = IsRising(ema9Arr,  i, fallingLen);
         bool rw = IsRising(wma45Arr, i, fallingLen);
         double hUc = HighestN(diffUp, i,     expansionLen);
         double hUp = HighestN(diffUp, i + 1, expansionLen);
         bool eu = hUc != EMPTY_VALUE && hUp != EMPTY_VALUE && hUc > hUp;
         outUp[i] = rr && re && rw && eu;
        }
     }
  }

//+------------------------------------------------------------------+
//| CalcRSISignalFast                                                |
//| Phiên bản tối ưu: nhận pre-computed downExpandArr/upExpandArr   |
//| Không tự build expand arrays → O(1) per bar thay vì O(lookback) |
//+------------------------------------------------------------------+
RSISignalResult CalcRSISignalFast(
   const double &rsiArr[],
   const double &ema9Arr[],
   const double &wma45Arr[],
   const bool   &inDown[],
   const bool   &inUp[],
   int    idx,
   double distThreshold,
   int    prevTrendLookback = 50)
  {
   RSISignalResult result;
   result.rsi   = rsiArr[idx];
   result.ema9  = ema9Arr[idx];
   result.wma45 = wma45Arr[idx];
   result.isBuy  = false;
   result.isSell = false;

   int arrSize = ArraySize(rsiArr);
   if(idx + 1 >= arrSize)
      return result;

   // Buy Signal
   bool crossUp   = rsiArr[idx] > ema9Arr[idx]   && rsiArr[idx+1] <= ema9Arr[idx+1];
   bool curlingIn = MathAbs(wma45Arr[idx] - ema9Arr[idx]) < MathAbs(wma45Arr[idx+1] - ema9Arr[idx+1]);
   bool prevDown  = rsiArr[idx+1] < ema9Arr[idx+1] && ema9Arr[idx+1] < wma45Arr[idx+1];
   bool hadDownExp = FindPrevTrend(inDown, idx, prevTrendLookback);
   bool ema9Up    = ema9Arr[idx] >= ema9Arr[idx+1];
   bool distOK    = MathAbs(wma45Arr[idx] - ema9Arr[idx]) <= distThreshold;
   result.isBuy = crossUp && curlingIn && prevDown && hadDownExp && ema9Up && distOK;

   // Sell Signal
   bool crossDown  = rsiArr[idx] < ema9Arr[idx]   && rsiArr[idx+1] >= ema9Arr[idx+1];
   bool prevUp     = rsiArr[idx+1] > ema9Arr[idx+1] && ema9Arr[idx+1] > wma45Arr[idx+1];
   bool hadUpExp   = FindPrevTrend(inUp, idx, prevTrendLookback);
   bool ema9Down   = ema9Arr[idx] <= ema9Arr[idx+1];
   result.isSell = crossDown && curlingIn && prevUp && hadUpExp && ema9Down && distOK;

   return result;
  }

//+------------------------------------------------------------------+
//| SendTelegramMessage                                              |
//| Gửi tin nhắn đến Telegram bot.                                  |
//| Trả về true nếu HTTP 200.                                        |
//| Lưu ý: cần thêm URL vào danh sách WebRequest trong Terminal     |
//+------------------------------------------------------------------+
bool SendTelegramMessage(string token, string chatId, string message)
  {
   string url = "https://api.telegram.org/bot" + token + "/sendMessage";

   // Encode params thành URL-encoded string
   string encodedMsg = message;
   // Thay thế ký tự đặc biệt cơ bản
   StringReplace(encodedMsg, " ",  "+");
   StringReplace(encodedMsg, "\n", "%0A");
   StringReplace(encodedMsg, "&",  "%26");
   StringReplace(encodedMsg, "=",  "%3D");

   string params = "chat_id=" + chatId + "&text=" + encodedMsg;

   char   postData[];
   char   resultData[];
   string resultHeaders;

   StringToCharArray(params, postData, 0, StringLen(params));

   string reqHeaders = "Content-Type: application/x-www-form-urlencoded\r\n";

   int timeout = 5000; // ms

   int httpCode = WebRequest(
                     "POST",
                     url,
                     reqHeaders,
                     timeout,
                     postData,
                     resultData,
                     resultHeaders
                  );

   return (httpCode == 200);
  }
//+------------------------------------------------------------------+
#endif // RSISIGNAL_MQH
