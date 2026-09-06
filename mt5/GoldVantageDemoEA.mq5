#property copyright "gold-trading-bot3"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

input group "SECURITE — DEMO UNIQUEMENT"
input bool   EnableDemoOrders      = false;
input string RequiredServerText    = "VantageMarkets-Demo";
input ulong  MagicNumber           = 2314001;

input group "STRATEGIE XAUUSD M1"
input int    FastEmaPeriod         = 5;
input int    SlowEmaPeriod         = 13;
input int    MomentumBars          = 3;
input double MinConfidence         = 0.15;

input group "SESSION"
input int    EntryWindowMinutes    = 60;
input int    MaxEntries            = 10;
input int    CooldownMinutes       = 6;
input int    MaxHoldMinutes        = 60;

input group "RISQUE"
input double LotsPerEntry          = 0.01;
input double MaxTotalLots          = 0.10;
input double MaxSessionLoss        = 25.0;
input int    StopLossPoints        = 300;
input int    TakeProfitPoints      = 600;
input int    MaxSpreadPoints       = 80;
input int    MaxSlippagePoints     = 20;

input group "SUIVI"
input bool   SendPushNotifications = true;
input bool   CloseOnRemoval        = false;

CTrade trade;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
datetime session_start = 0;
datetime last_entry_time = 0;
datetime last_bar_time = 0;
int entry_count = 0;
double session_start_equity = 0.0;

enum TradeSignal
  {
   SIGNAL_HOLD = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

string Upper(string value)
  {
   StringToUpper(value);
   return value;
  }

void Notify(string message)
  {
   Print(message);
   if(SendPushNotifications && !MQLInfoInteger(MQL_TESTER))
      SendNotification("Gold Bot Demo: " + message);
  }

bool IsDemoAccount()
  {
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
      return false;
   string server = Upper(AccountInfoString(ACCOUNT_SERVER));
   string required = Upper(RequiredServerText);
   return StringFind(server, required) >= 0;
  }

bool IsGoldChart()
  {
   return StringFind(Upper(_Symbol), "XAUUSD") >= 0;
  }

int OnInit()
  {
   if(!IsDemoAccount())
     {
      Alert("BLOCAGE: cet EA fonctionne uniquement sur ", RequiredServerText, " en mode Demo.");
      return INIT_FAILED;
     }
   if(!IsGoldChart())
     {
      Alert("BLOCAGE: attachez cet EA a un graphique XAUUSD.");
      return INIT_FAILED;
     }
   if(FastEmaPeriod < 2 || SlowEmaPeriod <= FastEmaPeriod || MomentumBars < 1)
      return INIT_PARAMETERS_INCORRECT;
   if(MaxEntries < 1 || MaxEntries > 10 || LotsPerEntry <= 0 || MaxTotalLots <= 0)
      return INIT_PARAMETERS_INCORRECT;
   if(EntryWindowMinutes < 1 || CooldownMinutes < 1 || MaxHoldMinutes < 1)
      return INIT_PARAMETERS_INCORRECT;

   fast_handle = iMA(_Symbol, PERIOD_M1, FastEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slow_handle = iMA(_Symbol, PERIOD_M1, SlowEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE)
      return INIT_FAILED;

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   session_start = TimeCurrent();
   session_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   Notify(EnableDemoOrders ? "initialise — ordres DEMO actifs" : "initialise — observation seulement");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(CloseOnRemoval && IsDemoAccount())
      CloseManagedPositions("retrait de l'EA");
   if(fast_handle != INVALID_HANDLE) IndicatorRelease(fast_handle);
   if(slow_handle != INVALID_HANDLE) IndicatorRelease(slow_handle);
  }

double NormalizeLots(double lots)
  {
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return 0;
   lots = MathMax(minimum, MathMin(maximum, lots));
   return NormalizeDouble(MathFloor(lots / step) * step, 2);
  }

double ManagedLots()
  {
   double lots = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      lots += PositionGetDouble(POSITION_VOLUME);
     }
   return lots;
  }

bool HasOppositePosition(TradeSignal signal)
  {
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(signal == SIGNAL_BUY && type == POSITION_TYPE_SELL) return true;
      if(signal == SIGNAL_SELL && type == POSITION_TYPE_BUY) return true;
     }
   return false;
  }

void CloseManagedPositions(string reason)
  {
   bool closed_any = false;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(trade.PositionClose(ticket)) closed_any = true;
      else Print("Echec cloture #", ticket, ": ", trade.ResultRetcodeDescription());
     }
   if(closed_any) Notify("position cloturee — " + reason);
  }

void EnforceMaximumHold()
  {
   datetime now = TimeCurrent();
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(now >= opened + MaxHoldMinutes * 60)
        {
         if(trade.PositionClose(ticket)) Notify("duree maximale atteinte — cloture #" + (string)ticket);
         else Print("Echec cloture #", ticket, ": ", trade.ResultRetcodeDescription());
        }
     }
  }

TradeSignal GetSignal(double &confidence)
  {
   double fast[1], slow[1];
   if(CopyBuffer(fast_handle, 0, 1, 1, fast) != 1) return SIGNAL_HOLD;
   if(CopyBuffer(slow_handle, 0, 1, 1, slow) != 1) return SIGNAL_HOLD;
   double close_now = iClose(_Symbol, PERIOD_M1, 1);
   double close_then = iClose(_Symbol, PERIOD_M1, 1 + MomentumBars);
   if(close_now <= 0 || close_then <= 0) return SIGNAL_HOLD;

   double spread = (fast[0] - slow[0]) / close_now;
   double momentum = (close_now - close_then) / close_then;
   double atr = iATRValue(14);
   double noise = MathMax(atr / close_now, 0.0001);
   confidence = MathMin(MathAbs(spread) / noise, 1.0);
   if(spread > 0 && momentum > 0 && confidence >= MinConfidence) return SIGNAL_BUY;
   if(spread < 0 && momentum < 0 && confidence >= MinConfidence) return SIGNAL_SELL;
   return SIGNAL_HOLD;
  }

double iATRValue(int period)
  {
   int handle = iATR(_Symbol, PERIOD_M1, period);
   if(handle == INVALID_HANDLE) return 0;
   double value[1];
   int copied = CopyBuffer(handle, 0, 1, 1, value);
   IndicatorRelease(handle);
   return copied == 1 ? value[0] : 0;
  }

bool RiskAllowsEntry()
  {
   datetime now = TimeCurrent();
   if(now >= session_start + EntryWindowMinutes * 60) return false;
   if(entry_count >= MaxEntries) return false;
   if(last_entry_time > 0 && now < last_entry_time + CooldownMinutes * 60) return false;
   if(session_start_equity - AccountInfoDouble(ACCOUNT_EQUITY) >= MaxSessionLoss) return false;
   if(ManagedLots() + LotsPerEntry > MaxTotalLots + 0.0000001) return false;
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread < 0 || spread > MaxSpreadPoints) return false;
   return true;
  }

void SubmitEntry(TradeSignal signal, double confidence)
  {
   if(!EnableDemoOrders)
     {
      Print("DRY-RUN ", signal == SIGNAL_BUY ? "BUY" : "SELL", " confidence=", confidence);
      return;
     }
   if(!IsDemoAccount())
     {
      ExpertRemove();
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double lots = NormalizeLots(LotsPerEntry);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   bool success = false;
   if(signal == SIGNAL_BUY)
     {
      double sl = StopLossPoints > 0 ? NormalizeDouble(tick.ask - StopLossPoints * point, digits) : 0;
      double tp = TakeProfitPoints > 0 ? NormalizeDouble(tick.ask + TakeProfitPoints * point, digits) : 0;
      success = trade.Buy(lots, _Symbol, 0, sl, tp, "GoldBot Demo");
     }
   else
     {
      double sl = StopLossPoints > 0 ? NormalizeDouble(tick.bid + StopLossPoints * point, digits) : 0;
      double tp = TakeProfitPoints > 0 ? NormalizeDouble(tick.bid - TakeProfitPoints * point, digits) : 0;
      success = trade.Sell(lots, _Symbol, 0, sl, tp, "GoldBot Demo");
     }

   if(success)
     {
      entry_count++;
      last_entry_time = TimeCurrent();
      Notify((signal == SIGNAL_BUY ? "BUY" : "SELL") + " DEMO " + DoubleToString(lots, 2) +
             " lot — entree " + (string)entry_count + "/" + (string)MaxEntries);
     }
   else Print("Ordre refuse: ", trade.ResultRetcodeDescription());
  }

void OnTick()
  {
   if(!IsDemoAccount())
     {
      Alert("Compte non Demo detecte — EA retire.");
      ExpertRemove();
      return;
     }

   EnforceMaximumHold();
   datetime current_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(current_bar <= 0 || current_bar == last_bar_time) return;
   last_bar_time = current_bar;

   double confidence = 0;
   TradeSignal signal = GetSignal(confidence);
   if(signal == SIGNAL_HOLD) return;
   if(HasOppositePosition(signal))
     {
      CloseManagedPositions("signal oppose");
      return;
     }
   if(RiskAllowsEntry()) SubmitEntry(signal, confidence);
  }

