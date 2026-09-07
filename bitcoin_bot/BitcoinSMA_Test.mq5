#property strict
#property version   "1.00"
#property description "BTCUSD SMA 10/20 strategy for MT5 Strategy Tester only"

#include <Trade/Trade.mqh>

input int FastPeriod = 10;
input int SlowPeriod = 20;
input double TestVolume = 0.01;
input long MagicNumber = 23141020;

CTrade trade;
int fast_handle = INVALID_HANDLE;
int slow_handle = INVALID_HANDLE;
datetime last_bar = 0;

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER))
   {
      Print("SECURITY: this EA is restricted to the MT5 Strategy Tester.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   fast_handle = iMA(_Symbol, PERIOD_H1, FastPeriod, 0, MODE_SMA, PRICE_CLOSE);
   slow_handle = iMA(_Symbol, PERIOD_H1, SlowPeriod, 0, MODE_SMA, PRICE_CLOSE);

   if(fast_handle == INVALID_HANDLE || slow_handle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(fast_handle != INVALID_HANDLE) IndicatorRelease(fast_handle);
   if(slow_handle != INVALID_HANDLE) IndicatorRelease(slow_handle);
}

bool HasPosition(const ENUM_POSITION_TYPE position_type)
{
   if(!PositionSelect(_Symbol)) return(false);
   if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) return(false);
   return((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == position_type);
}

void CloseTestPosition()
{
   if(PositionSelect(_Symbol) &&
      (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      trade.PositionClose(_Symbol);
}

void OnTick()
{
   datetime current_bar = iTime(_Symbol, PERIOD_H1, 0);
   if(current_bar == 0 || current_bar == last_bar) return;
   last_bar = current_bar;

   double fast[2], slow[2];
   if(CopyBuffer(fast_handle, 0, 1, 2, fast) != 2) return;
   if(CopyBuffer(slow_handle, 0, 1, 2, slow) != 2) return;

   bool cross_up = fast[0] <= slow[0] && fast[1] > slow[1];
   bool cross_down = fast[0] >= slow[0] && fast[1] < slow[1];

   if(cross_up)
   {
      if(HasPosition(POSITION_TYPE_SELL)) CloseTestPosition();
      if(!PositionSelect(_Symbol)) trade.Buy(TestVolume, _Symbol);
   }
   else if(cross_down)
   {
      if(HasPosition(POSITION_TYPE_BUY)) CloseTestPosition();
      if(!PositionSelect(_Symbol)) trade.Sell(TestVolume, _Symbol);
   }
}
