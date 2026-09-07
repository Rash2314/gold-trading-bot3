#property strict
#property version   "1.00"
#property description "Autonomous BTCUSD momentum experiment restricted to MT5 demo accounts"

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M5;
input int FastEmaPeriod = 9;
input int SlowEmaPeriod = 21;
input int RsiPeriod = 14;
input int AdxPeriod = 14;
input int AtrPeriod = 14;
input double LongRsiMinimum = 52.0;
input double ShortRsiMaximum = 48.0;
input double MinimumAdx = 15.0;
input double StopAtrMultiple = 1.30;
input double RewardRiskRatio = 1.30;
input double RiskPerTradePct = 0.75;
input double FallbackVolume = 0.01;
input double DailyLossLimitPct = 5.0;
input double MaximumEquityDrawdownPct = 15.0;
input int MaximumTradesPerDay = 35;
input int MaximumPortfolioTradesPerDay = 50;
input int CooldownBars = 1;
input int MaximumSpreadPoints = 5000;
input int SlippagePoints = 150;
input long MagicNumber = 23142027;

CTrade trade;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
int rsi_handle = INVALID_HANDLE;
int adx_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;
datetime last_bar = 0;
datetime last_entry_bar = 0;
int day_key = -1;
int trades_today = 0;
double day_start_equity = 0.0;
double initial_equity = 0.0;

bool IsDemoOrTester()
{
   if(MQLInfoInteger(MQL_TESTER)) return(true);
   return((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
}

int CurrentDayKey()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return(now.year * 1000 + now.day_of_year);
}

void ResetDailyCountersIfNeeded()
{
   int current_key = CurrentDayKey();
   if(current_key != day_key)
   {
      day_key = current_key;
      trades_today = 0;
      day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("NEW DAY: equity reference=", day_start_equity);
   }
}

string PortfolioCounterName()
{
   return("AUTOBOT_TRADES_" + LongToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) +
          "_" + IntegerToString(CurrentDayKey()));
}

int PortfolioTradesToday()
{
   string name = PortfolioCounterName();
   if(!GlobalVariableCheck(name)) GlobalVariableSet(name, 0.0);
   return((int)GlobalVariableGet(name));
}

void IncrementPortfolioTrades()
{
   string name = PortfolioCounterName();
   GlobalVariableSet(name, (double)(PortfolioTradesToday() + 1));
}

bool RiskLimitsAllowEntry()
{
   ResetDailyCountersIfNeeded();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(trades_today >= MaximumTradesPerDay) return(false);
   if(PortfolioTradesToday() >= MaximumPortfolioTradesPerDay) return(false);
   if(day_start_equity > 0.0 && equity <= day_start_equity * (1.0 - DailyLossLimitPct / 100.0))
      return(false);
   if(initial_equity > 0.0 && equity <= initial_equity * (1.0 - MaximumEquityDrawdownPct / 100.0))
      return(false);
   if((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaximumSpreadPoints)
      return(false);
   return(true);
}

double NormalizeVolume(double requested)
{
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return(FallbackVolume);
   if(requested < minimum) return(0.0);
   double volume = MathFloor(requested / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));
   int digits = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   return(NormalizeDouble(volume, digits));
}

double RiskBasedVolume(double stop_distance)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(stop_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0)
      return(NormalizeVolume(FallbackVolume));

   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * RiskPerTradePct / 100.0;
   double loss_per_lot = (stop_distance / tick_size) * tick_value;
   if(loss_per_lot <= 0.0) return(NormalizeVolume(FallbackVolume));
   return(NormalizeVolume(risk_money / loss_per_lot));
}

bool CooldownComplete()
{
   if(last_entry_bar == 0) return(true);
   return(iBarShift(_Symbol, SignalTimeframe, last_entry_bar, false) >= CooldownBars);
}

bool ReadIndicators(double &fast_now, double &fast_before,
                    double &slow_now, double &slow_before,
                    double &rsi_now, double &adx_now, double &atr_now)
{
   double fast[2], slow[2], rsi[1], adx[1], atr[1];
   if(CopyBuffer(fast_handle, 0, 1, 2, fast) != 2) return(false);
   if(CopyBuffer(slow_handle, 0, 1, 2, slow) != 2) return(false);
   if(CopyBuffer(rsi_handle, 0, 1, 1, rsi) != 1) return(false);
   if(CopyBuffer(adx_handle, 0, 1, 1, adx) != 1) return(false);
   if(CopyBuffer(atr_handle, 0, 1, 1, atr) != 1) return(false);
   fast_before = fast[0]; fast_now = fast[1];
   slow_before = slow[0]; slow_now = slow[1];
   rsi_now = rsi[0]; adx_now = adx[0]; atr_now = atr[0];
   return(atr_now > 0.0);
}

bool OpenPosition(bool buy_signal, double atr_value, datetime current_bar)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = buy_signal ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_distance = atr_value * StopAtrMultiple;
   double target_distance = stop_distance * RewardRiskRatio;
   double volume = RiskBasedVolume(stop_distance);
   if(volume <= 0.0)
   {
      Print("ENTRY SKIPPED: broker minimum volume exceeds the configured risk budget.");
      return(false);
   }
   double stop = NormalizeDouble(buy_signal ? entry - stop_distance : entry + stop_distance, digits);
   double target = NormalizeDouble(buy_signal ? entry + target_distance : entry - target_distance, digits);

   bool placed = buy_signal
      ? trade.Buy(volume, _Symbol, 0.0, stop, target, "BTC demo momentum")
      : trade.Sell(volume, _Symbol, 0.0, stop, target, "BTC demo momentum");

   if(placed)
   {
      trades_today++;
      IncrementPortfolioTrades();
      last_entry_bar = current_bar;
      Print("DEMO ENTRY ", buy_signal ? "BUY" : "SELL", " #", trades_today,
            " volume=", volume, " SL=", stop, " TP=", target);
   }
   else
      Print("ORDER REJECTED: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   return(placed);
}

int OnInit()
{
   if(!IsDemoOrTester())
   {
      Print("SECURITY: refused because this is not an MT5 demo account or the Strategy Tester.");
      return(INIT_FAILED);
   }
   if(FastEmaPeriod <= 1 || SlowEmaPeriod <= FastEmaPeriod || RiskPerTradePct <= 0.0 ||
      StopAtrMultiple <= 0.0 || RewardRiskRatio <= 0.0 || MaximumTradesPerDay < 1 ||
      MaximumPortfolioTradesPerDay < MaximumTradesPerDay)
      return(INIT_PARAMETERS_INCORRECT);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   fast_handle = iMA(_Symbol, SignalTimeframe, FastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slow_handle = iMA(_Symbol, SignalTimeframe, SlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsi_handle = iRSI(_Symbol, SignalTimeframe, RsiPeriod, PRICE_CLOSE);
   adx_handle = iADX(_Symbol, SignalTimeframe, AdxPeriod);
   atr_handle = iATR(_Symbol, SignalTimeframe, AtrPeriod);
   if(fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE ||
      rsi_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
      return(INIT_FAILED);

   initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ResetDailyCountersIfNeeded();
   Print("BTC DEMO BOT READY: symbol max/day=", MaximumTradesPerDay,
         " portfolio max/day=", MaximumPortfolioTradesPerDay,
         " risk/trade=", RiskPerTradePct, "% daily stop=", DailyLossLimitPct, "%");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(fast_handle != INVALID_HANDLE) IndicatorRelease(fast_handle);
   if(slow_handle != INVALID_HANDLE) IndicatorRelease(slow_handle);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);
   if(adx_handle != INVALID_HANDLE) IndicatorRelease(adx_handle);
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

void OnTick()
{
   datetime current_bar = iTime(_Symbol, SignalTimeframe, 0);
   if(current_bar == 0 || current_bar == last_bar) return;
   last_bar = current_bar;

   if(PositionSelect(_Symbol) || !RiskLimitsAllowEntry() || !CooldownComplete()) return;

   double fast_now, fast_before, slow_now, slow_before, rsi_now, adx_now, atr_now;
   if(!ReadIndicators(fast_now, fast_before, slow_now, slow_before, rsi_now, adx_now, atr_now)) return;

   bool long_signal = fast_now > slow_now && fast_now >= fast_before &&
                      rsi_now >= LongRsiMinimum && adx_now >= MinimumAdx;
   bool short_signal = fast_now < slow_now && fast_now <= fast_before &&
                       rsi_now <= ShortRsiMaximum && adx_now >= MinimumAdx;
   if(long_signal) OpenPosition(true, atr_now, current_bar);
   else if(short_signal) OpenPosition(false, atr_now, current_bar);
}
