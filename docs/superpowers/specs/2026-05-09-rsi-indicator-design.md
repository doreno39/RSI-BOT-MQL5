# RSI Long/Short Indicator — MQL5 Design Spec

**Date**: 2026-05-09  
**Status**: Approved  
**Reference**: `templates/rsi-indicator-tradingview.txt`

---

## Context

Port chiến lược RSI từ TradingView Pine Script sang MQL5 dưới dạng custom indicator. Indicator sẽ phát hiện tín hiệu mua/bán dựa trên sự sắp xếp của RSI(14), EMA9(RSI), WMA45(RSI) và sự mở rộng của xu hướng, sau đó gửi alert qua Telegram. Indicator cũng xuất dữ liệu qua buffer để EA có thể đọc trong backtest.

---

## Cấu trúc file

```
rsi-bot/
├── templates/
│   └── rsi-indicator-tradingview.txt   ← nguồn tham chiếu
├── MQL5/
│   ├── Include/
│   │   └── RSISignal.mqh               ← thư viện logic dùng chung
│   ├── Indicators/
│   │   └── RSI_LongShort.mq5           ← indicator chính
│   └── Experts/
│       └── RSI_EA.mq5                  ← EA (phase sau)
└── docs/
    └── superpowers/specs/
        └── 2026-05-09-rsi-indicator-design.md
```

---

## Logic tín hiệu (port từ TradingView)

### Các giá trị tính toán
- `rsi14` = RSI(close, 14)
- `ema9` = EMA(rsi14, 9)
- `wma45` = WMA(rsi14, 45)

### Điều kiện Buy Signal
1. RSI cắt lên trên EMA9: `rsi14 > ema9 AND rsi14[1] <= ema9[1]`
2. EMA9 đang "curling in" (khoảng cách thu hẹp): `|wma45 - ema9| < |wma45[1] - ema9[1]|`
3. Trước đó đang downtrend: `rsi14[1] < ema9[1] < wma45[1]`
4. Đã từng có downtrend mở rộng trước đó (`prev_downtrend = true`)
5. EMA9 slope >= 0
6. Khoảng cách EMA9-WMA45 <= `distance_threshold` (mặc định 10.0)

### Điều kiện Sell Signal (đối xứng)
1. RSI cắt xuống dưới EMA9: `rsi14 < ema9 AND rsi14[1] >= ema9[1]`
2. EMA9 đang "curling in"
3. Trước đó đang uptrend: `rsi14[1] > ema9[1] > wma45[1]`
4. Đã từng có uptrend mở rộng trước đó (`prev_uptrend = true`)
5. EMA9 slope <= 0
6. Khoảng cách EMA9-WMA45 <= `distance_threshold`

### Phát hiện Downtrend Expanding
```
downtrend = rsi14 < ema9 AND ema9 < wma45
falling_rsi = rsi14[0] < rsi14[1] < rsi14[2]  (falling_length = 3)
falling_ema9 = tương tự
falling_wma45 = tương tự
expansion_down = max(wma45-rsi14, 5 bars) > max(wma45-rsi14, 5 bars)[1]
is_downtrend_expanding = downtrend AND falling_rsi AND falling_ema9 AND falling_wma45 AND expansion_down
```

---

## MQL5 Implementation Notes

### Ánh xạ Pine Script → MQL5

| Pine Script | MQL5 |
|---|---|
| `ta.rsi(close, 14)` | `iRSI(symbol, tf, 14, PRICE_CLOSE)` + `CopyBuffer()` |
| `ta.ema(rsi14, 9)` | Tự tính EMA trên mảng RSI (exponential smoothing) |
| `ta.wma(rsi14, 45)` | Tự tính WMA trên mảng RSI (weighted average) |
| `ta.falling(x, 3)` | `x[0] < x[1] AND x[1] < x[2]` |
| `ta.highest(x, 5)` | Duyệt mảng 5 phần tử tìm max |
| `ta.valuewhen(cond, val, n)` | Duyệt lịch sử tìm lần thứ n thỏa cond |

### Indicator Buffers

| Index | Tên | Mục đích |
|---|---|---|
| 0 | RSI14 | Giá trị RSI |
| 1 | EMA9 | EMA9 của RSI |
| 2 | WMA45 | WMA45 của RSI |
| 3 | BuySignal | 1.0 tại bar có tín hiệu mua, EMPTY_VALUE còn lại |
| 4 | SellSignal | 1.0 tại bar có tín hiệu bán, EMPTY_VALUE còn lại |

### Thư viện RSISignal.mqh

```mql5
struct RSISignalResult {
    double rsi;
    double ema9;
    double wma45;
    bool   isBuy;
    bool   isSell;
};

// Hàm chính tính toán toàn bộ tín hiệu
RSISignalResult CalcRSISignal(
    const double &rsiBuffer[],
    int           bars,
    int           fallingLength,
    int           expansionLength,
    double        distanceThreshold
);
```

---

## Input Parameters

```mql5
input int    RSI_Period          = 14;
input int    EMA_Period          = 9;
input int    WMA_Period          = 45;
input int    Falling_Length      = 3;
input int    Expansion_Length    = 5;
input double Distance_Threshold  = 10.0;
input double Overbought          = 80.0;
input double Oversold            = 20.0;
// Telegram
input string TelegramBotToken    = "";
input string TelegramChatId      = "";
input bool   EnableTelegram      = false;
```

---

## Telegram Alert

- Giao thức: HTTPS POST đến `https://api.telegram.org/bot{TOKEN}/sendMessage`
- Nội dung tin nhắn:
  ```
  📈 BUY Signal
  Symbol: EURUSD | TF: M15
  RSI: 28.5 | EMA9: 31.2 | WMA45: 38.7
  Price: 1.08523
  Time: 2026-05-09 14:30
  ```
- Chống spam: chỉ gửi 1 lần mỗi bar (lưu `last_alert_bar`)
- Yêu cầu MT5: bật WebRequest + whitelist `https://api.telegram.org`

---

## Verification

1. **Compile**: 0 errors, 0 warnings trong MetaEditor
2. **Visual check**: Gắn vào EURUSD M15, so sánh RSI/EMA9/WMA45 với TradingView cùng symbol/TF
3. **Signal check**: Tìm bar lịch sử có tín hiệu trên TradingView → verify buffer 3/4 có giá trị 1.0 tại đúng bar đó
4. **Telegram**: Cấu hình bot token + chat ID, chờ tín hiệu tiếp theo hoặc force bằng cách đổi tham số
5. **Buffer test**: Dùng Strategy Tester, in giá trị buffer 3/4 ra log để kiểm tra

---

## Phase tiếp theo (ngoài scope hiện tại)

- `RSI_EA.mq5`: đọc buffer từ indicator qua `iCustom()`, tự động vào/ra lệnh, quản lý risk (SL/TP, lot size)
- Backtest EA với Strategy Tester
