#property strict
#property version   "1.10"
#property description "Risk-reduced XAUUSD Donchian/ATR EA restricted to MT5 Strategy Tester"

// Strategy concepts independently implemented for this project.
// References: https://github.com/EarnForex/Donchian-Ultimate
//             https://github.com/EarnForex/ATR-Trailing-Stop

#include <Trade/Trade.mqh>

input ENUM_TIMEFRAMES EntryTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H1;
input int DonchianPeriod = 20;
input int FastTrendEma = 50;
input int SlowTrendEma = 200;
input int AdxPeriod = 14;
input double MinimumAdx = 20.0;
input int AtrPeriod = 14;
input double InitialStopAtr = 2.0;
input double RewardRiskRatio = 2.0;
input double TrailActivationR = 1.0;
input double TrailAtrMultiple = 2.0;
input double TotalRiskBudgetPct = 0.30;
input bool UseMinimumBrokerLot = true;
input int MaximumOpenPositions = 1;
input int CooldownBars = 3;
input int MaximumTradesPerDay = 8;
input double DailyProfitCapMoney = 120.0;
input double DailyLossLimitPct = 3.0;
input double MaximumEquityDrawdownPct = 20.0;
input int MaximumSpreadPoints = 1000;
input int SlippagePoints = 50;
input long MagicNumber = 23142128;

CTrade trade;
int atr_handle = INVALID_HANDLE;
int adx_handle = INVALID_HANDLE;
int fast_trend_handle = INVALID_HANDLE;
int slow_trend_handle = INVALID_HANDLE;
datetime last_bar = 0;
datetime last_entry_bar = 0;
int day_key = -1;
int trades_today = 0;
double day_start_equity = 0.0;
double initial_equity = 0.0;

bool IsTesterOnly()
{
   return((bool)MQLInfoInteger(MQL_TESTER));
}

int CurrentDayKey()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return(now.year * 1000 + now.day_of_year);
}

void ResetDayIfNeeded()
{
   int key = CurrentDayKey();
   if(key == day_key) return;
   day_key = key;
   trades_today = 0;
   day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
}

int CountOwnPositions()
{
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return(count);
}

bool DirectionCompatible(bool buy_signal)
{
   ENUM_POSITION_TYPE wanted = buy_signal ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != wanted)
         return(false);
   }
   return(true);
}

bool DailyLimitsAllowEntry()
{
   ResetDayIfNeeded();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(trades_today >= MaximumTradesPerDay) return(false);
   if(day_start_equity > 0.0 && equity >= day_start_equity + DailyProfitCapMoney)
      return(false);
   if(day_start_equity > 0.0 &&
      equity <= day_start_equity * (1.0 - DailyLossLimitPct / 100.0))
      return(false);
   return((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= MaximumSpreadPoints);
}

bool HardRiskLimitBreached()
{
   ResetDayIfNeeded();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   bool daily_breach = day_start_equity > 0.0 &&
      equity <= day_start_equity * (1.0 - DailyLossLimitPct / 100.0);
   bool total_breach = initial_equity > 0.0 &&
      equity <= initial_equity * (1.0 - MaximumEquityDrawdownPct / 100.0);
   return(daily_breach || total_breach);
}

void CloseOwnPositionsAtRiskLimit()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(!trade.PositionClose(ticket))
         PrintFormat("RISK LIMIT: failed to close ticket %I64u, retcode=%u.",
                     ticket, trade.ResultRetcode());
   }
}

double NormalizeVolume(double requested)
{
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0 || minimum <= 0.0 || requested <= 0.0) return(0.0);
   int digits = (int)MathMax(0.0, MathRound(-MathLog10(step)));
   if(requested < minimum)
   {
      if(!UseMinimumBrokerLot) return(0.0);
      PrintFormat("VOLUME: calculated %.4f lot is below broker minimum %.4f; using minimum lot for this tester-only run.",
                  requested, minimum);
      return(NormalizeDouble(minimum, digits));
   }
   double volume = MathFloor(requested / step) * step;
   volume = MathMax(minimum, MathMin(maximum, volume));
   return(NormalizeDouble(volume, digits));
}

double RiskBasedVolume(double stop_distance)
{
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value <= 0.0) tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(stop_distance <= 0.0 || tick_size <= 0.0 || tick_value <= 0.0) return(0.0);
   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) *
                       (TotalRiskBudgetPct / MaximumOpenPositions) / 100.0;
   double loss_per_lot = stop_distance / tick_size * tick_value;
   if(loss_per_lot <= 0.0) return(0.0);
   return(NormalizeVolume(risk_money / loss_per_lot));
}

bool ReadValue(int handle, int buffer, int shift, double &value)
{
   double data[1];
   if(CopyBuffer(handle, buffer, shift, 1, data) != 1) return(false);
   value = data[0];
   return(true);
}

bool GetBreakoutSignal(bool &buy_signal, double &atr_value)
{
   double adx, fast_ema, slow_ema;
   if(!ReadValue(atr_handle, 0, 1, atr_value) ||
      !ReadValue(adx_handle, 0, 1, adx) ||
      !ReadValue(fast_trend_handle, 0, 1, fast_ema) ||
      !ReadValue(slow_trend_handle, 0, 1, slow_ema)) return(false);
   if(atr_value <= 0.0 || adx < MinimumAdx) return(false);

   double prior_high = -DBL_MAX;
   double prior_low = DBL_MAX;
   for(int shift=2; shift<DonchianPeriod+2; shift++)
   {
      double high = iHigh(_Symbol, EntryTimeframe, shift);
      double low = iLow(_Symbol, EntryTimeframe, shift);
      if(high == 0.0 || low == 0.0) return(false);
      prior_high = MathMax(prior_high, high);
      prior_low = MathMin(prior_low, low);
   }

   double close = iClose(_Symbol, EntryTimeframe, 1);
   if(close > prior_high && fast_ema > slow_ema)
   {
      buy_signal = true;
      return(true);
   }
   if(close < prior_low && fast_ema < slow_ema)
   {
      buy_signal = false;
      return(true);
   }
   return(false);
}

bool CooldownComplete()
{
   if(last_entry_bar == 0) return(true);
   return(iBarShift(_Symbol, EntryTimeframe, last_entry_bar, false) >= CooldownBars);
}

bool OpenBreakout(bool buy_signal, double atr_value, datetime current_bar)
{
   if(CountOwnPositions() >= MaximumOpenPositions || !DirectionCompatible(buy_signal))
      return(false);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double entry = buy_signal ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                             : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stop_distance = atr_value * InitialStopAtr;
   double target_distance = stop_distance * RewardRiskRatio;
   double volume = RiskBasedVolume(stop_distance);
   if(volume <= 0.0) return(false);
   double stop = NormalizeDouble(buy_signal ? entry-stop_distance : entry+stop_distance, digits);
   double target = NormalizeDouble(buy_signal ? entry+target_distance : entry-target_distance, digits);
   bool placed = buy_signal
      ? trade.Buy(volume, _Symbol, 0.0, stop, target, "Gold Donchian ATR test")
      : trade.Sell(volume, _Symbol, 0.0, stop, target, "Gold Donchian ATR test");
   if(placed)
   {
      trades_today++;
      last_entry_bar = current_bar;
   }
   return(placed);
}

void ManageTrailingStops()
{
   double atr;
   if(!ReadValue(atr_handle, 0, 1, atr) || atr <= 0.0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double target = PositionGetDouble(POSITION_TP);
      double price = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double initial_risk = target > 0.0 ? MathAbs(target-open)/RewardRiskRatio
                                         : MathAbs(open-current_sl);
      double profit_distance = type == POSITION_TYPE_BUY ? price-open : open-price;
      if(initial_risk <= 0.0 || profit_distance < initial_risk*TrailActivationR) continue;

      double proposed = type == POSITION_TYPE_BUY ? price-atr*TrailAtrMultiple
                                                   : price+atr*TrailAtrMultiple;
      proposed = NormalizeDouble(proposed, digits);
      bool improves = type == POSITION_TYPE_BUY ? proposed > current_sl && proposed < price
                                                : proposed < current_sl && proposed > price;
      if(improves) trade.PositionModify(ticket, proposed, target);
   }
}

int OnInit()
{
   if(!IsTesterOnly())
   {
      Print("SECURITY: GoldDonchianATR_Test runs only inside MT5 Strategy Tester.");
      return(INIT_FAILED);
   }
   if(DonchianPeriod < 5 || FastTrendEma < 2 || SlowTrendEma <= FastTrendEma ||
      AtrPeriod < 2 || InitialStopAtr <= 0.0 || RewardRiskRatio <= 0.0 ||
      MaximumOpenPositions < 1 || TotalRiskBudgetPct <= 0.0 || CooldownBars < 1 ||
      DailyLossLimitPct <= 0.0 || MaximumEquityDrawdownPct <= 0.0)
      return(INIT_PARAMETERS_INCORRECT);

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   atr_handle = iATR(_Symbol, EntryTimeframe, AtrPeriod);
   adx_handle = iADX(_Symbol, EntryTimeframe, AdxPeriod);
   fast_trend_handle = iMA(_Symbol, TrendTimeframe, FastTrendEma, 0, MODE_EMA, PRICE_CLOSE);
   slow_trend_handle = iMA(_Symbol, TrendTimeframe, SlowTrendEma, 0, MODE_EMA, PRICE_CLOSE);
   if(atr_handle == INVALID_HANDLE || adx_handle == INVALID_HANDLE ||
      fast_trend_handle == INVALID_HANDLE || slow_trend_handle == INVALID_HANDLE)
      return(INIT_FAILED);
   initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   ResetDayIfNeeded();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
   if(adx_handle != INVALID_HANDLE) IndicatorRelease(adx_handle);
   if(fast_trend_handle != INVALID_HANDLE) IndicatorRelease(fast_trend_handle);
   if(slow_trend_handle != INVALID_HANDLE) IndicatorRelease(slow_trend_handle);
}

void OnTick()
{
   if(HardRiskLimitBreached())
   {
      CloseOwnPositionsAtRiskLimit();
      return;
   }
   ManageTrailingStops();
   datetime current_bar = iTime(_Symbol, EntryTimeframe, 0);
   if(current_bar == 0 || current_bar == last_bar) return;
   last_bar = current_bar;
   if(!DailyLimitsAllowEntry() || CountOwnPositions() >= MaximumOpenPositions ||
      !CooldownComplete()) return;

   bool buy_signal = false;
   double atr_value = 0.0;
   if(GetBreakoutSignal(buy_signal, atr_value))
      OpenBreakout(buy_signal, atr_value, current_bar);
}
