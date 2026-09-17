//+------------------------------------------------------------------+
//|                                             Fractal Breakout.mq5 |
//|                                                 Daily Ranger EAs |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright     "Daily Ranger EAs"
#property link          "https://www.mql5.com"
#property version       "1.01"
#property description   "First Fractal Breakout Intraday Trading Strategy"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Tools\DateTime.mqh>

//--- Enums
enum FractalType
  {
   fractal_high = 0,
   fractal_low  = 1
  };

//--- Named trading session for the overlap filter.
//--- Hours below are approximate MT5 server-time windows for a typical
//--- GMT+2/+3 broker. If your broker's server time offset differs, edit
//--- the hour constants inside GetNamedSessionHours().
enum ENUM_SESSION_NAME
  {
   SESSION_SYDNEY  = 0,   // Sydney
   SESSION_TOKYO   = 1,   // Tokyo / Asia
   SESSION_LONDON  = 2,   // London
   SESSION_NEWYORK = 3    // New York
  };

//--- Structs
struct Fractal
  {
   bool              isSet;
   double            value;
   datetime          time;

                     Fractal(bool IsSet=false, double Value=0, datetime Time=0):
                     isSet(IsSet),
                     value(Value),
                     time(Time) {}
  };

struct SessionTime
  {
   bool              isSessionSet;
   datetime          start;
   datetime          end;
   datetime          strategyStart;

                     SessionTime(bool IsSessionSet=false, datetime Start=0, datetime End=0, datetime StrategyStart=0):
                     isSessionSet(IsSessionSet),
                     start(Start),
                     strategyStart(StrategyStart),
                     end(End) {}
  };

struct DirectionStats
  {
   int               slCount;
   int               tpCount;
   int               closeProfitCount;
   int               closeLossCount;
   double            slGross;
   double            tpGross;
   double            closeProfitGross;
   double            closeLossGross;

                     DirectionStats(int SlCount=0, int TpCount=0, int CloseProfitCount=0, int CloseLossCount=0, double SlGross=0, double TpGross=0, double CloseProfitGross=0, double CloseLossGross=0):
                     slCount(SlCount),
                     tpCount(TpCount),
                     closeProfitCount(CloseProfitCount),
                     closeLossCount(CloseLossCount),
                     slGross(SlGross),
                     tpGross(TpGross),
                     closeProfitGross(CloseProfitGross),
                     closeLossGross(CloseLossGross) {}
  };

struct ExpertStats
  {
   DirectionStats    buy;
   DirectionStats    sell;

                     ExpertStats():
                     buy(DirectionStats()),
                     sell(DirectionStats()) {}
  };

struct VisualObjects
  {
   bool              isSession;
   bool              isUpFractal;
   bool              isDnFractal;

                     VisualObjects(bool IsSession=false, bool IsUpFractal=false, bool IsDnFractal=false):
                     isSession(IsSession),
                     isUpFractal(IsUpFractal),
                     isDnFractal(IsDnFractal) {}
  };

//--- Input definition
input group    "Start Time"
input int      InpStartHour               = 9;        // Start Hour (0 - 23)
input int      InpStartMin                = 0;        // Start Min (0 - 59)
input group    "End Time"
input int      InpEndHour                 = 18;       // End Hour (0 - 23)
input int      InpEndMin                  = 45;       // End Min (0 - 59)
input group    "Trade Parameters"
input double   InpFixedLot                = 0.01;     // Fixed Lot Size
input int      InpAtrPeriod               = 14;       // ATR Period
input group    "Strategy Parameters"
input double   InpAtrPercent              = 15;       // ATR Percentage
input double   InpTpMultiplier            = 10;       // TP Multiplier
input group    "Fractal Settings"
input int      InpFractalShift            = 3;        // Fractal Shift (bars back, min 3 = confirmed)
input group    "ADX Filter"
input bool     InpUseAdxFilter            = false;    // Use ADX Filter
input ENUM_TIMEFRAMES InpAdxTimeframe     = PERIOD_H1; // ADX Timeframe
input int      InpAdxPeriod               = 14;       // ADX Period
input double   InpAdxThreshold            = 25;       // ADX Threshold (min trend strength)
input bool     InpAdxUseDirection         = true;     // Use +DI/-DI for Buy/Sell Direction
input group    "MA Trend Filter (Higher TF)"
input bool     InpUseMaFilter             = false;    // Use MA Trend Filter
input ENUM_TIMEFRAMES InpMaTimeframe      = PERIOD_H4; // MA Timeframe
input int      InpMaPeriod                = 200;      // MA Period
input group    "Volatility Filter (ATR Ratio)"
input bool     InpUseVolatilityFilter     = false;    // Use Volatility Filter
input ENUM_TIMEFRAMES InpVolAtrTimeframe  = PERIOD_D1; // Volatility ATR Timeframe
input int      InpVolAtrPeriod            = 14;       // Volatility ATR Period
input int      InpVolAtrAvgPeriod         = 20;       // Volatility ATR Average Lookback (bars)
input double   InpVolAtrRatioMin          = 1.0;      // Min ATR Ratio (current / average)
input group    "Session Filter"
input bool     InpUseSessionFilter        = false;    // Use Session Filter
input int      InpSessionStartHour        = 8;        // Session Start Hour (0 - 23)
input int      InpSessionStartMin         = 0;        // Session Start Min (0 - 59)
input int      InpSessionEndHour          = 17;       // Session End Hour (0 - 23)
input int      InpSessionEndMin           = 0;        // Session End Min (0 - 59)
input group    "Session Overlap Filter"
input bool     InpUseOverlapFilter        = false;         // Use Session Overlap Filter
input ENUM_SESSION_NAME InpOverlapSessionA = SESSION_LONDON;  // Overlap Session A
input ENUM_SESSION_NAME InpOverlapSessionB = SESSION_NEWYORK; // Overlap Session B
input group    "Trailing Stop"
input bool     InpUseTrailingStop         = true;     // Use Trailing Stop
input double   InpTrailAtrPercent         = 10;       // Trailing Stop ATR Percent
input group    "Visual Objects"
input bool     InpShowObjects             = true;     // Draw Visual Objects
input group    "Expert Identification"
input ulong    InpMagicNumber             = 12345;    // Magic Number

//--- Indicator handles
int AtrHandle;
int FractalHandle;
int AdxHandle;
int MaHandle;
int VolAtrHandle;

//--- Globals
CTrade Trade;

ENUM_TIMEFRAMES FractalTimeframe = PERIOD_M5;
ENUM_TIMEFRAMES AtrTimeframe     = PERIOD_D1;

string ObjPrefix        = "fractal_breakout_";
string StartSuffix      = "_start";
string EndSuffix        = "_end";
string UpFractalSuffix  = "_up_fractal";
string DnFractalSuffix  = "_dn_fractal";
string StartLabel       = "Session Start";
string EndLabel         = "Session Close";
string UpFractalLabel   = "Up Fractal Limit";
string DnFractalLabel   = "Dn Fractal Limit";
color  StartColor       = clrCyan;
color  EndColor         = clrViolet;
color  UpFractalColor   = clrAzure;
color  DnFractalColor   = clrBlanchedAlmond;

int StartMinOffset = 15;

Fractal gblUpFractal;
Fractal gblDnFractal;

bool gblIsOpen;
bool gblIsStrategy;
bool gblIsBuyTrade;
bool gblIsSellTrade;

double gblBuyPeak;
double gblSellTrough;

CDateTime gblLastOpenDate;
CDateTime gblLastSessionSet;

datetime gblLastBuyTime;
datetime gblLastSellTime;
datetime gblLastFractalBar;

datetime gblTestStartTime;
datetime gblTestEndTime;

SessionTime    gblSession;
ExpertStats    gblStats;
VisualObjects  gblVisuals;

bool   gblInitOK = false;
string gblRunID  = "";
string WfoFolder = "WFO\\";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Check account type
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("You need a hedging account for this EA");
      return INIT_AGENT_NOT_SUITABLE;
     }

//--- Input Validation
   if(InpMagicNumber == 0)
     {
      Print("Please enter a Magic Number other than 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpStartHour < 0 || InpStartHour > 23)
     {
      Print("Please enter start hour between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpStartMin < 0 || InpStartMin > 59)
     {
      Print("Please enter start min between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpEndHour < 0 || InpEndHour > 23)
     {
      Print("Please enter end hour between 0 and 23");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpEndMin < 0 || InpEndMin > 59)
     {
      Print("Please enter end min between 0 and 59");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpFixedLot <= 0)
     {
      Print("Please enter fixed lot size above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpFixedLot < SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN) ||
      InpFixedLot > SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX))
     {
      Print("Please enter fixed lot within symbol volume range");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpAtrPeriod <= 0)
     {
      Print("Please enter ATR period above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpAtrPercent <= 0)
     {
      Print("Please enter ATR percent above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpTpMultiplier < 0)
     {
      Print("Please enter TP multiplier greater than or equal to 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseTrailingStop && InpTrailAtrPercent <= 0)
     {
      Print("Please enter trailing ATR percent above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpFractalShift < 3)
     {
      Print("Please enter fractal shift of 3 or more (values below 3 use an unconfirmed, repainting fractal)");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseAdxFilter && (InpAdxPeriod <= 0 || InpAdxThreshold <= 0))
     {
      Print("Please enter ADX period and threshold above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseMaFilter && InpMaPeriod <= 0)
     {
      Print("Please enter MA period above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseVolatilityFilter && (InpVolAtrPeriod <= 0 || InpVolAtrAvgPeriod <= 0 || InpVolAtrRatioMin <= 0))
     {
      Print("Please enter volatility ATR period, average lookback and ratio above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionEndHour < 0 || InpSessionEndHour > 23 ||
      InpSessionStartMin  < 0 || InpSessionStartMin  > 59 || InpSessionEndMin  < 0 || InpSessionEndMin  > 59)
     {
      Print("Please enter session filter hours/minutes within valid ranges");
      return INIT_PARAMETERS_INCORRECT;
     }

   Trade.SetExpertMagicNumber(InpMagicNumber);

//--- Indicator handles
   AtrHandle      = iATR(Symbol(), AtrTimeframe, InpAtrPeriod);
   if(AtrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle");
      return INIT_FAILED;
     }

   FractalHandle  = iFractals(Symbol(), FractalTimeframe);
   if(FractalHandle == INVALID_HANDLE)
     {
      Print("Failed to create fractal handle: use testing timeframe M5 with Open prices model, or 1-minute OHLC / Every tick for higher timeframes");
      return INIT_FAILED;
     }

   AdxHandle = INVALID_HANDLE;
   if(InpUseAdxFilter)
     {
      AdxHandle = iADX(Symbol(), InpAdxTimeframe, InpAdxPeriod);
      if(AdxHandle == INVALID_HANDLE)
        {
         Print("Failed to create ADX handle");
         return INIT_FAILED;
        }
     }

   MaHandle = INVALID_HANDLE;
   if(InpUseMaFilter)
     {
      MaHandle = iMA(Symbol(), InpMaTimeframe, InpMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(MaHandle == INVALID_HANDLE)
        {
         Print("Failed to create MA handle");
         return INIT_FAILED;
        }
     }

   VolAtrHandle = INVALID_HANDLE;
   if(InpUseVolatilityFilter)
     {
      VolAtrHandle = iATR(Symbol(), InpVolAtrTimeframe, InpVolAtrPeriod);
      if(VolAtrHandle == INVALID_HANDLE)
        {
         Print("Failed to create volatility ATR handle");
         return INIT_FAILED;
        }
     }

//--- Initialize global variables
   InitGlobals();
   gblLastFractalBar = iTime(Symbol(), FractalTimeframe, 0);
   gblStats = ExpertStats();
   gblTestStartTime = TimeCurrent();
   gblTestEndTime = TimeCurrent();

   gblInitOK = true;
   gblRunID  = GenerateRunID();
   Print("Run ID: ", gblRunID);

//--- Enable chart property to show object labels
   if(InpShowObjects)
      ChartSetInteger(ChartID(), CHART_SHOW_OBJECT_DESCR, true);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator resources
   if(AtrHandle      != INVALID_HANDLE)
      IndicatorRelease(AtrHandle);
   if(FractalHandle  != INVALID_HANDLE)
      IndicatorRelease(FractalHandle);
   if(AdxHandle      != INVALID_HANDLE)
      IndicatorRelease(AdxHandle);
   if(MaHandle       != INVALID_HANDLE)
      IndicatorRelease(MaHandle);
   if(VolAtrHandle   != INVALID_HANDLE)
      IndicatorRelease(VolAtrHandle);

//--- Delete visual objects
   ObjectsDeleteAll(ChartID(), ObjPrefix);

//--- Print strategy stats and save results to CSV
   if(gblInitOK)
     {
      PrintStats();
      SaveResultsToCSV();
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check session bounds
   if(!gblIsOpen)
     {
      CDateTime curDay;
      curDay.Date(TimeCurrent());

      if(gblLastSessionSet.DateTime() != curDay.DateTime())
        {
         SetSessionTimes();
         gblLastSessionSet.Date(curDay.DateTime());
        }

      if(gblSession.isSessionSet &&
         (TimeCurrent() >= gblSession.start) &&
         (TimeCurrent() <  gblSession.end))
        {
         Print("Market Open: ", gblSession.start);
         gblLastOpenDate.Date(gblSession.start);
         gblIsOpen = true;
        }
     }
   else
     {
      if(TimeCurrent() >= gblSession.end)
        {
         Print("Market Closed: ", gblSession.end);
         CloseAllPositions();
         InitGlobals();
         return;
        }

      if(!gblIsStrategy && (TimeCurrent() >= gblSession.strategyStart))
        {
         Print("Strategy Start: ", gblSession.strategyStart);
         gblIsStrategy = true;
        }
     }

//--- Early return if strategy time is not reached
   if(!gblIsStrategy)
      return;

//--- Set fractal values
   bool newFractalBar = IsNewFractalBar();
   if(newFractalBar)
     {
      if(!gblUpFractal.isSet)
        {
         gblUpFractal = GetStrategyFractal(FractalHandle, fractal_high, InpFractalShift, FractalTimeframe, gblSession.start);
        }

      if(!gblDnFractal.isSet)
        {
         gblDnFractal = GetStrategyFractal(FractalHandle, fractal_low, InpFractalShift, FractalTimeframe, gblSession.start);
        }
     }

//--- Open position on fractal breakout
   MqlTick curTick;
   if(!SymbolInfoTick(Symbol(), curTick))
      return;

//--- Update trailing stop
   if(InpUseTrailingStop)
     {
      UpdateTrailExtremes(curTick);
      if(newFractalBar)
         ManageTrailingStops();
     }

   if(gblUpFractal.isSet && !gblIsBuyTrade)
     {
      if(curTick.bid >= gblUpFractal.value)
        {
         if(CheckAdxFilter(true) && CheckMaFilter(true) && CheckVolatilityFilter() &&
            CheckSessionFilter() && CheckOverlapFilter())
           {
            gblIsBuyTrade = true;
            if(OpenTrade(POSITION_TYPE_BUY, curTick))
              {
               gblLastBuyTime = TimeCurrent();
               Print("Buy trade taken at ", gblLastBuyTime);
              }
            else
              {
               gblIsBuyTrade = false;
              }
           }
        }
     }

   if(gblDnFractal.isSet && !gblIsSellTrade)
     {
      if(curTick.bid <= gblDnFractal.value)
        {
         if(CheckAdxFilter(false) && CheckMaFilter(false) && CheckVolatilityFilter() &&
            CheckSessionFilter() && CheckOverlapFilter())
           {
            gblIsSellTrade = true;
            if(OpenTrade(POSITION_TYPE_SELL, curTick))
              {
               gblLastSellTime = TimeCurrent();
               Print("Sell trade taken at ", gblLastSellTime);
              }
            else
              {
               gblIsSellTrade = false;
              }
           }
        }
     }

//--- Draw graphical objects
   if(InpShowObjects)
      DrawVisualObjects(gblSession, gblUpFractal, gblDnFractal, gblVisuals);
  }

//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {
//--- Check for trade closing transaction of current symbol and magic
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket))
      return;

   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != Symbol())
      return;
   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != (long) InpMagicNumber)
      return;
   if((ENUM_DEAL_ENTRY) HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
      (ENUM_DEAL_ENTRY) HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY)
      return;

//--- Accumulate stats based on trade direction and closing reason
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON) HistoryDealGetInteger(dealTicket, DEAL_REASON);
   bool wasLong   = (ENUM_DEAL_TYPE) HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_SELL;
   bool wasShort  = (ENUM_DEAL_TYPE) HistoryDealGetInteger(dealTicket, DEAL_TYPE) == DEAL_TYPE_BUY;

   switch(reason)
     {
      case DEAL_REASON_TP:
         if(wasLong)
           {
            gblStats.buy.tpCount += 1;
            gblStats.buy.tpGross += profit;
           }

         if(wasShort)
           {
            gblStats.sell.tpCount += 1;
            gblStats.sell.tpGross += profit;
           }
         return;

      case DEAL_REASON_SL:
         if(wasLong)
           {
            gblStats.buy.slCount += 1;
            gblStats.buy.slGross += profit;
           }

         if(wasShort)
           {
            gblStats.sell.slCount += 1;
            gblStats.sell.slGross += profit;
           }
         return;

      case DEAL_REASON_EXPERT:
      case DEAL_REASON_CLIENT:
         if(profit >= 0)
           {
            if(wasLong)
              {
               gblStats.buy.closeProfitCount += 1;
               gblStats.buy.closeProfitGross += profit;
              }

            if(wasShort)
              {
               gblStats.sell.closeProfitCount += 1;
               gblStats.sell.closeProfitGross += profit;
              }
           }
         else
           {
            if(wasLong)
              {
               gblStats.buy.closeLossCount += 1;
               gblStats.buy.closeLossGross += profit;
              }

            if(wasShort)
              {
               gblStats.sell.closeLossCount += 1;
               gblStats.sell.closeLossGross += profit;
              }
           }
         return;
     }
  }

//+------------------------------------------------------------------+
//| Opens trade of given position type and tick structure            |
//+------------------------------------------------------------------+
bool OpenTrade(ENUM_POSITION_TYPE posType, MqlTick &curTick)
  {
   double atr = GetATR(AtrHandle);
   if(atr == EMPTY_VALUE)
     {
      Print("Could not read ATR value");
      return false;
     }

   double slDist = InpAtrPercent / 100 * atr;
   if(!CheckStopsLevel(slDist))
      return false;

   switch(posType)
     {
      case POSITION_TYPE_BUY:
        {
         double sl = curTick.ask - slDist;
         double tp = curTick.ask + InpTpMultiplier * slDist;
         if(!CheckFreezeLevel(tp - curTick.bid) || !CheckFreezeLevel(curTick.bid - sl))
            return false;

         double lots = GetLotSize();
         if(lots == 0)
            return false;

         if(!CheckMarginForTrade(curTick.ask, lots, ORDER_TYPE_BUY))
            return false;

         if(!Trade.Buy(lots, Symbol(), curTick.ask, sl, tp))
           {
            Print("Failed to open position: ", Trade.ResultRetcodeDescription());
            return false;
           }
         break;
        }

      case POSITION_TYPE_SELL:
        {
         double sl = curTick.bid + slDist;
         double tp = curTick.bid - InpTpMultiplier * slDist;
         if(!CheckFreezeLevel(curTick.ask - tp) || !CheckFreezeLevel(sl - curTick.ask))
            return false;

         double lots = GetLotSize();
         if(lots == 0)
            return false;

         if(!CheckMarginForTrade(curTick.bid, lots, ORDER_TYPE_SELL))
            return false;

         if(!Trade.Sell(lots, Symbol(), curTick.bid, sl, tp))
           {
            Print("Failed to open position: ", Trade.ResultRetcodeDescription());
            return false;
           }
         break;
        }
     }
   if((Trade.ResultRetcode() != TRADE_RETCODE_DONE))
     {
      Print("Trade opening failed: ", Trade.ResultRetcodeDescription());
      return false;
     }

//--- Initialize trailing stop extreme prices
   if(posType == POSITION_TYPE_BUY)
      gblBuyPeak = curTick.ask;
   else
      gblSellTrough = curTick.bid;
   return true;
  }

//+------------------------------------------------------------------+
//| Sets start, strategy and end times for the current trading day   |
//+------------------------------------------------------------------+
void SetSessionTimes()
  {
   CDateTime start;
   CDateTime end;
   CDateTime strategy;

   start.Date(TimeCurrent());
   start.Hour(InpStartHour);
   start.Min(InpStartMin);
   start.Sec(0);

   strategy.DateTime(start.DateTime());
   strategy.MinInc(StartMinOffset);

   end.Date(TimeCurrent());
   end.Hour(InpEndHour);
   end.Min(InpEndMin);
   end.Sec(0);

//--- Increment ending date by 1 day if closing crosses over midnight
   if((InpEndHour < InpStartHour) ||
      ((InpStartHour == InpEndHour) && (InpEndMin <= InpStartMin)))
     {
      end.DayInc(1);
     }

   gblSession.start           = start.DateTime();
   gblSession.strategyStart   = strategy.DateTime();
   gblSession.end             = end.DateTime();
   gblSession.isSessionSet    = true;
  }

//+------------------------------------------------------------------+
//| Returns true if current time falls within the given daily window |
//| (handles windows that cross midnight)                            |
//+------------------------------------------------------------------+
bool IsTimeInHourWindow(int startHour, int startMin, int endHour, int endMin)
  {
   CDateTime start;
   CDateTime end;

   start.Date(TimeCurrent());
   start.Hour(startHour);
   start.Min(startMin);
   start.Sec(0);

   end.Date(TimeCurrent());
   end.Hour(endHour);
   end.Min(endMin);
   end.Sec(0);

   if((endHour < startHour) || (endHour == startHour && endMin <= startMin))
      end.DayInc(1);

   datetime now = TimeCurrent();
   return (now >= start.DateTime()) && (now < end.DateTime());
  }

//+------------------------------------------------------------------+
//| ADX Filter: gates entries by trend strength and optionally       |
//| by +DI/-DI direction. Returns true if the filter is disabled     |
//| or the entry passes the filter                                   |
//+------------------------------------------------------------------+
bool CheckAdxFilter(bool isBuy)
  {
   if(!InpUseAdxFilter)
      return true;

   double adxMain[];
   if(CopyBuffer(AdxHandle, MAIN_LINE, 1, 1, adxMain) <= 0)
      return false;

   if(adxMain[0] < InpAdxThreshold)
      return false;

   if(!InpAdxUseDirection)
      return true;

   double plusDI[];
   double minusDI[];
   if(CopyBuffer(AdxHandle, PLUSDI_LINE, 1, 1, plusDI) <= 0)
      return false;
   if(CopyBuffer(AdxHandle, MINUSDI_LINE, 1, 1, minusDI) <= 0)
      return false;

   if(isBuy)
      return plusDI[0] > minusDI[0];
   return minusDI[0] > plusDI[0];
  }

//+------------------------------------------------------------------+
//| MA Trend Filter: gates entries by price vs. higher-TF EMA        |
//+------------------------------------------------------------------+
bool CheckMaFilter(bool isBuy)
  {
   if(!InpUseMaFilter)
      return true;

   double ma[];
   if(CopyBuffer(MaHandle, 0, 1, 1, ma) <= 0)
      return false;

   double price = iClose(Symbol(), InpMaTimeframe, 1);
   if(price == 0)
      return false;

   if(isBuy)
      return price > ma[0];
   return price < ma[0];
  }

//+------------------------------------------------------------------+
//| Volatility Filter: gates entries by ATR expansion vs its average |
//+------------------------------------------------------------------+
bool CheckVolatilityFilter()
  {
   if(!InpUseVolatilityFilter)
      return true;

   int total = InpVolAtrAvgPeriod + 1;
   double atrBuf[];
   if(CopyBuffer(VolAtrHandle, 0, 1, total, atrBuf) <= 0)
      return false;

   double current = atrBuf[0];
   double sum = 0;
   for(int i = 1; i < total; i++)
      sum += atrBuf[i];
   double avg = sum / (total - 1);

   if(avg <= 0)
      return false;

   return (current / avg) >= InpVolAtrRatioMin;
  }

//+------------------------------------------------------------------+
//| Session Filter: gates entries to a single daily sub-window       |
//+------------------------------------------------------------------+
bool CheckSessionFilter()
  {
   if(!InpUseSessionFilter)
      return true;
   return IsTimeInHourWindow(InpSessionStartHour, InpSessionStartMin, InpSessionEndHour, InpSessionEndMin);
  }

//+------------------------------------------------------------------+
//| Returns the fixed server-time hour window for a named session    |
//+------------------------------------------------------------------+
void GetNamedSessionHours(ENUM_SESSION_NAME session, int &startHour, int &startMin, int &endHour, int &endMin)
  {
   startMin = 0;
   endMin   = 0;
   switch(session)
     {
      case SESSION_SYDNEY:
         startHour = 0;  endHour = 9;
         break;
      case SESSION_TOKYO:
         startHour = 2;  endHour = 11;
         break;
      case SESSION_LONDON:
         startHour = 10; endHour = 19;
         break;
      case SESSION_NEWYORK:
         startHour = 15; endHour = 0; // wraps past midnight
         break;
      default:
         startHour = 0;  endHour = 0;
         break;
     }
  }

//+------------------------------------------------------------------+
//| Session Overlap Filter: gates entries to the intersection of two |
//| named trading sessions (e.g. London / New York overlap)          |
//+------------------------------------------------------------------+
bool CheckOverlapFilter()
  {
   if(!InpUseOverlapFilter)
      return true;

   int aStartHour, aStartMin, aEndHour, aEndMin;
   int bStartHour, bStartMin, bEndHour, bEndMin;
   GetNamedSessionHours(InpOverlapSessionA, aStartHour, aStartMin, aEndHour, aEndMin);
   GetNamedSessionHours(InpOverlapSessionB, bStartHour, bStartMin, bEndHour, bEndMin);

   bool inA = IsTimeInHourWindow(aStartHour, aStartMin, aEndHour, aEndMin);
   bool inB = IsTimeInHourWindow(bStartHour, bStartMin, bEndHour, bEndMin);
   return inA && inB;
  }

//+------------------------------------------------------------------+
//| Returns fixed lot size normalized to symbol volume constraints   |
//+------------------------------------------------------------------+
double GetLotSize()
  {
   double volMin  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   if(InpFixedLot <= 0 || volStep <= 0 || volMin <= 0)
     {
      Print("Invalid fixed lot or volume constraints");
      return 0;
     }
   if(InpFixedLot < volMin || InpFixedLot > volMax)

     {
      Print("Fixed lot is outside the symbol volume range");
      return 0;
     }

   double lots = MathFloor(InpFixedLot / volStep) * volStep;

   if(lots < volMin)
      return 0;
   if(lots > volMax)
      return volMax;
   return lots;
  }

//+------------------------------------------------------------------+
//| Checks if sufficient free margin is available to initiate trade  |
//+------------------------------------------------------------------+
bool CheckMarginForTrade(double openPrice, double lots, ENUM_ORDER_TYPE orderType)
  {
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double reqMargin;
   if(!OrderCalcMargin(orderType, Symbol(), lots, openPrice, reqMargin))
     {
      Print("Failed to calculate position margin: ", GetLastError());
      return false;
     }

   if(reqMargin > freeMargin)
     {
      Print("Insufficient funds");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Checks for broker stop levels                                    |
//+------------------------------------------------------------------+
bool CheckStopsLevel(double slDist)
  {
   int stopsLevel = (int) SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel == 0)
      return true;
   return (slDist >= stopsLevel * Point()) && (slDist * InpTpMultiplier >= stopsLevel * Point());
  }

//+------------------------------------------------------------------+
//| Checks for broker freeze levels                                  |
//+------------------------------------------------------------------+
bool CheckFreezeLevel(double dist)
  {
   int freezeLevel = (int) SymbolInfoInteger(Symbol(), SYMBOL_TRADE_FREEZE_LEVEL);
   if(freezeLevel == 0)
      return true;
   return dist >= freezeLevel * Point();
  }

//+------------------------------------------------------------------+
//| Initializes global variables                                     |
//+------------------------------------------------------------------+
void InitGlobals()
  {
   gblIsOpen         = false;
   gblIsStrategy     = false;
   gblIsBuyTrade     = false;
   gblIsSellTrade    = false;
   gblBuyPeak        = 0;
   gblSellTrough     = 0;
   gblUpFractal      = Fractal();
   gblDnFractal      = Fractal();

   if(InpShowObjects)
      gblVisuals = VisualObjects();
  }

//+------------------------------------------------------------------+
//| Updates trailing stop extreme prices                             |
//+------------------------------------------------------------------+
void UpdateTrailExtremes(const MqlTick &curTick)
  {
   if(curTick.bid > gblBuyPeak)
      gblBuyPeak = curTick.bid;
   if(gblSellTrough == 0 || curTick.ask < gblSellTrough)
      gblSellTrough = curTick.ask;
  }

//+------------------------------------------------------------------+
//| Trails stop loss for open positions of this EA                   |
//+------------------------------------------------------------------+
void ManageTrailingStops()
  {
   double atr = GetATR(AtrHandle);
   if(atr == EMPTY_VALUE)
      return;

   double trailDist = InpTrailAtrPercent / 100 * atr;
   if(trailDist <= 0)
      return;

   MqlTick curTick;
   if(!SymbolInfoTick(Symbol(), curTick))
      return;

   double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0)
      tickSize = Point();

   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      CPositionInfo posInfo;
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != InpMagicNumber)
         continue;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         double newSl = gblBuyPeak - trailDist;
         double curSl = posInfo.StopLoss();
         if(curSl == 0 || newSl - curSl < tickSize)
            continue;
         if(!CheckFreezeLevel(curTick.bid - newSl))
            continue;
         if(Trade.PositionModify(posInfo.Ticket(), newSl, posInfo.TakeProfit()))
            Print("Trailing SL updated for buy position: ", posInfo.Ticket(), " -> ", newSl);
         else
            Print("Failed to update trailing SL: ", posInfo.Ticket(), "Err: ", Trade.ResultRetcodeDescription());
        }
      else
         if(posInfo.PositionType() == POSITION_TYPE_SELL)
           {
            double newSl = gblSellTrough + trailDist;
            double curSl = posInfo.StopLoss();
            if(curSl == 0 || curSl - newSl < tickSize)
               continue;
            if(!CheckFreezeLevel(newSl - curTick.ask))
               continue;
            if(Trade.PositionModify(posInfo.Ticket(), newSl, posInfo.TakeProfit()))
               Print("Trailing SL updated for sell position: ", posInfo.Ticket(), " -> ", newSl);
            else
               Print("Failed to update trailing SL: ", posInfo.Ticket(), "Err: ", Trade.ResultRetcodeDescription());
           }
     }
  }

//+------------------------------------------------------------------+
//| Closes all open positions of current symbol and magic number     |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal()-1; i >= 0; i--)
     {
      CPositionInfo posInfo;
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != InpMagicNumber)
         continue;
      if(!Trade.PositionClose(posInfo.Ticket()))
        {
         Print("Failed to close position: ", posInfo.Ticket(), "Err: ", Trade.ResultRetcodeDescription());
         continue;
        }
      if((Trade.ResultRetcode() != TRADE_RETCODE_DONE))
        {
         Print("Failed to close position: ", posInfo.Ticket(), "Err: ", Trade.ResultRetcodeDescription());
         continue;
        }
     }
  }

//+------------------------------------------------------------------+
//| Generates unique run id (time + tick count + file existence)      |
//+------------------------------------------------------------------+
string GenerateRunID()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string base = StringFormat("%04d%02d%02d_%02d%02d%02d",
                              dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   string id = base + StringFormat("_%05d", (GetTickCount() % 100000));
   int guard = 0;
   while(guard < 1000 && FileIsExist(GetRunFileName(GetRunModeLabel(), id), FILE_COMMON))
     {
      guard++;
      id = base + StringFormat("_%05d", ((GetTickCount() + guard) % 100000));
     }
   return id;
  }

//+------------------------------------------------------------------+
//| Returns run mode label: optimization pass or forward/regular run |
//+------------------------------------------------------------------+
string GetRunModeLabel()
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION))
      return "OPT";
   return "FWD";
  }

//+------------------------------------------------------------------+
//| Builds per-run CSV file name inside the WFO folder               |
//+------------------------------------------------------------------+
string GetRunFileName(string mode, string id)
  {
   return WfoFolder + StringFormat("Fractal_Breakout_%s_%s.csv", mode, id);
  }

//+------------------------------------------------------------------+
//| Appends one summary line to the monthly WFO report CSV           |
//+------------------------------------------------------------------+
void AppendSummaryReport(string mode)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string reportName = WfoFolder + StringFormat("Fractal_Breakout_Report_%04d%02d.csv", dt.year, dt.mon);

   bool needHeader = false;
   int handle = FileOpen(reportName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON);
   if(handle == INVALID_HANDLE)
     {
      handle = FileOpen(reportName, FILE_WRITE | FILE_CSV | FILE_COMMON);
      if(handle == INVALID_HANDLE)
        {
         Print("Failed to open report: ", reportName);
         return;
        }
      needHeader = true;
     }

   FileSeek(handle, 0, SEEK_END);

   if(needHeader)
      FileWrite(handle,
                "Mode", "Run ID", "Date", "Symbol", "Period",
                "Session Start", "Strategy Start", "Session End",
                "Start Hour", "Start Min", "End Hour", "End Min",
                "Fixed Lot", "ATR Period", "ATR Percent", "TP Multiplier",
                "Use Trailing", "Trail ATR Percent", "Magic",
                "Total Trades", "Win Count", "Loss Count", "Win Rate %",
                "Total P/L", "Buy Trades", "Buy P/L", "Sell Trades", "Sell P/L");

   int totalTrades = GetTotalTrades();
   int winCount    = GetWinCount();
   int lossCount   = totalTrades - winCount;
   double winRate  = (totalTrades > 0) ? (double) winCount / totalTrades * 100 : 0;
   double totalPL  = GetTotalProfit();
   double buyPL    = gblStats.buy.slGross + gblStats.buy.tpGross +
                     gblStats.buy.closeProfitGross + gblStats.buy.closeLossGross;
   double sellPL   = gblStats.sell.slGross + gblStats.sell.tpGross +
                     gblStats.sell.closeProfitGross + gblStats.sell.closeLossGross;
   int buyTrades   = gblStats.buy.slCount + gblStats.buy.tpCount +
                     gblStats.buy.closeProfitCount + gblStats.buy.closeLossCount;
   int sellTrades  = gblStats.sell.slCount + gblStats.sell.tpCount +
                     gblStats.sell.closeProfitCount + gblStats.sell.closeLossCount;

   FileWrite(handle,
             mode, gblRunID, TimeToString(gblTestStartTime, TIME_DATE), Symbol(), EnumToString(Period()),
             TimeToString(gblSession.start), TimeToString(gblSession.strategyStart), TimeToString(gblSession.end),
             InpStartHour, InpStartMin, InpEndHour, InpEndMin,
             InpFixedLot, InpAtrPeriod, InpAtrPercent, InpTpMultiplier,
             InpUseTrailingStop, InpTrailAtrPercent, InpMagicNumber,
             totalTrades, winCount, lossCount, winRate,
             totalPL, buyTrades, buyPL, sellTrades, sellPL);

   FileFlush(handle);
   FileClose(handle);
   Print("Summary appended: ", reportName);
  }

//+------------------------------------------------------------------+
//| Returns total number of closed trades across both directions     |
//+------------------------------------------------------------------+
int GetTotalTrades()
  {
   return gblStats.buy.slCount + gblStats.buy.tpCount +
          gblStats.buy.closeProfitCount + gblStats.buy.closeLossCount +
          gblStats.sell.slCount + gblStats.sell.tpCount +
          gblStats.sell.closeProfitCount + gblStats.sell.closeLossCount;
  }

//+------------------------------------------------------------------+
//| Returns total number of profitable closed trades                 |
//+------------------------------------------------------------------+
int GetWinCount()
  {
   return gblStats.buy.tpCount + gblStats.buy.closeProfitCount +
          gblStats.sell.tpCount + gblStats.sell.closeProfitCount;
  }

//+------------------------------------------------------------------+
//| Returns total gross profit/loss across both directions           |
//+------------------------------------------------------------------+
double GetTotalProfit()
  {
   return gblStats.buy.slGross + gblStats.buy.tpGross +
          gblStats.buy.closeProfitGross + gblStats.buy.closeLossGross +
          gblStats.sell.slGross + gblStats.sell.tpGross +
          gblStats.sell.closeProfitGross + gblStats.sell.closeLossGross;
  }
//+------------------------------------------------------------------+
//| Saves strategy results to CSV file                                |
//+------------------------------------------------------------------+
void SaveResultsToCSV()
  {
   gblTestEndTime = TimeCurrent();

   string mode = GetRunModeLabel();
   string filename = GetRunFileName(mode, gblRunID);

   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV | FILE_COMMON);
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to open CSV file: ", filename);
      return;
     }

   FileWrite(handle, "Parameter", "Value");
   FileWrite(handle, "Run ID", gblRunID);
   FileWrite(handle, "Mode", mode);
   FileWrite(handle, "Symbol", Symbol());
   FileWrite(handle, "Period", EnumToString(Period()));
   FileWrite(handle, "Start Time", TimeToString(gblSession.start));
   FileWrite(handle, "Strategy Start", TimeToString(gblSession.strategyStart));
   FileWrite(handle, "End Time", TimeToString(gblSession.end));
   FileWrite(handle, "");
   FileWrite(handle, "Input Parameters", "");
   FileWrite(handle, "Start Hour", InpStartHour);
   FileWrite(handle, "Start Min", InpStartMin);
   FileWrite(handle, "End Hour", InpEndHour);
   FileWrite(handle, "End Min", InpEndMin);
   FileWrite(handle, "Fixed Lot", InpFixedLot);
   FileWrite(handle, "ATR Period", InpAtrPeriod);
   FileWrite(handle, "ATR Percent", InpAtrPercent);
   FileWrite(handle, "TP Multiplier", InpTpMultiplier);
   FileWrite(handle, "Use Trailing Stop", InpUseTrailingStop);
   FileWrite(handle, "Trail ATR Percent", InpTrailAtrPercent);
   FileWrite(handle, "Magic Number", InpMagicNumber);
   FileWrite(handle, "");
   FileWrite(handle, "Performance Statistics", "");
   FileWrite(handle, "Total Trades", (gblStats.buy.slCount + gblStats.buy.tpCount +
                                      gblStats.buy.closeProfitCount + gblStats.buy.closeLossCount +
                                      gblStats.sell.slCount + gblStats.sell.tpCount +
                                      gblStats.sell.closeProfitCount + gblStats.sell.closeLossCount));

   double totalProfit = gblStats.buy.slGross + gblStats.buy.tpGross +
                       gblStats.buy.closeProfitGross + gblStats.buy.closeLossGross +
                       gblStats.sell.slGross + gblStats.sell.tpGross +
                       gblStats.sell.closeProfitGross + gblStats.sell.closeLossGross;
   FileWrite(handle, "Total Profit/Loss", totalProfit);

   int winCount = gblStats.buy.tpCount + gblStats.buy.closeProfitCount +
                  gblStats.sell.tpCount + gblStats.sell.closeProfitCount;
   int lossCount = gblStats.buy.slCount + gblStats.buy.closeLossCount +
                   gblStats.sell.slCount + gblStats.sell.closeLossCount;
   int totalTrades = winCount + lossCount;

   FileWrite(handle, "Win Count", winCount);
   FileWrite(handle, "Loss Count", lossCount);

   if(totalTrades > 0)
      FileWrite(handle, "Win Rate %", (double)winCount / totalTrades * 100);
   else
      FileWrite(handle, "Win Rate %", 0);

   FileWrite(handle, "");
   FileWrite(handle, "Long (Buy) Statistics", "");
   FileWrite(handle, "Buy SL Count", gblStats.buy.slCount);
   FileWrite(handle, "Buy SL Gross", gblStats.buy.slGross);
   FileWrite(handle, "Buy TP Count", gblStats.buy.tpCount);
   FileWrite(handle, "Buy TP Gross", gblStats.buy.tpGross);
   FileWrite(handle, "Buy Close Profit Count", gblStats.buy.closeProfitCount);
   FileWrite(handle, "Buy Close Profit Gross", gblStats.buy.closeProfitGross);
   FileWrite(handle, "Buy Close Loss Count", gblStats.buy.closeLossCount);
   FileWrite(handle, "Buy Close Loss Gross", gblStats.buy.closeLossGross);

   FileWrite(handle, "");
   FileWrite(handle, "Short (Sell) Statistics", "");
   FileWrite(handle, "Sell SL Count", gblStats.sell.slCount);
   FileWrite(handle, "Sell SL Gross", gblStats.sell.slGross);
   FileWrite(handle, "Sell TP Count", gblStats.sell.tpCount);
   FileWrite(handle, "Sell TP Gross", gblStats.sell.tpGross);
   FileWrite(handle, "Sell Close Profit Count", gblStats.sell.closeProfitCount);
   FileWrite(handle, "Sell Close Profit Gross", gblStats.sell.closeProfitGross);
   FileWrite(handle, "Sell Close Loss Count", gblStats.sell.closeLossCount);
   FileWrite(handle, "Sell Close Loss Gross", gblStats.sell.closeLossGross);

   FileFlush(handle);
   FileClose(handle);
   if(!FileIsExist(filename, FILE_COMMON))
      Print("Warning: file not found after save: ", filename);
   Print("Run saved: ", filename, " (ID ", gblRunID, ")");
   Print("Files folder (Common): ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\WFO");

   AppendSummaryReport(mode);
  }

//+------------------------------------------------------------------+
//| Prints the strategy stats during the expert lifetime             |
//+------------------------------------------------------------------+
void PrintStats()
  {
   Print("=== Summary Stats ==="
         "\n--- Long ---",
         "\nSl count: ",            gblStats.buy.slCount,
         "\nSl gross: ",            gblStats.buy.slGross,
         "\nTp count: ",            gblStats.buy.tpCount,
         "\nTp gross: ",            gblStats.buy.tpGross,
         "\nClose profit count: ",  gblStats.buy.closeProfitCount,
         "\nClose profit gross: ",  gblStats.buy.closeProfitGross,
         "\nClose loss count: ",    gblStats.buy.closeLossCount,
         "\nClose loss gross: ",    gblStats.buy.closeLossGross,
         "\n--- Short ---",
         "\nSl count: ",            gblStats.sell.slCount,
         "\nSl gross: ",            gblStats.sell.slGross,
         "\nTp count: ",            gblStats.sell.tpCount,
         "\nTp gross: ",            gblStats.sell.tpGross,
         "\nClose profit count: ",  gblStats.sell.closeProfitCount,
         "\nClose profit gross: ",  gblStats.sell.closeProfitGross,
         "\nClose loss count: ",    gblStats.sell.closeLossCount,
         "\nClose loss gross: ",    gblStats.sell.closeLossGross,
         "\n--- Total ---",
         "\nSl count: ",            gblStats.sell.slCount + gblStats.buy.slCount,
         "\nSl gross: ",            gblStats.sell.slGross + gblStats.buy.slGross,
         "\nTp count: ",            gblStats.sell.tpCount + gblStats.buy.tpCount,
         "\nTp gross: ",            gblStats.sell.tpGross + gblStats.buy.tpGross,
         "\nClose profit count: ",  gblStats.sell.closeProfitCount + gblStats.buy.closeProfitCount,
         "\nClose profit gross: ",  gblStats.sell.closeProfitGross + gblStats.buy.closeProfitGross,
         "\nClose loss count: ",    gblStats.sell.closeLossCount   + gblStats.buy.closeLossCount,
         "\nClose loss gross: ",    gblStats.sell.closeLossGross   + gblStats.buy.closeLossGross);
  }

//+------------------------------------------------------------------+
//| Draws objects for strategy visualization                         |
//+------------------------------------------------------------------+
void DrawVisualObjects(const SessionTime &session, const Fractal &up, const Fractal &dn, VisualObjects &visuals)
  {
   long chartId   = ChartID();
   int  subWindow = 0;
   if(session.isSessionSet && !visuals.isSession)
     {
      string startName = ObjPrefix + TimeToString(session.start) + StartSuffix;
      ObjectCreate(chartId, startName, OBJ_VLINE, subWindow, session.start, 0);
      ObjectSetInteger(chartId, startName, OBJPROP_COLOR, StartColor);
      ObjectSetString(chartId, startName, OBJPROP_TEXT, StartLabel);

      string endName = ObjPrefix + TimeToString(session.end) + EndSuffix;
      ObjectCreate(chartId, endName, OBJ_VLINE, subWindow, session.end, 0);
      ObjectSetInteger(chartId, endName, OBJPROP_COLOR, EndColor);
      ObjectSetString(chartId, endName, OBJPROP_TEXT, EndLabel);

      visuals.isSession = true;
     }

   if(up.isSet && !visuals.isUpFractal)
     {
      string upFractalName = ObjPrefix + TimeToString(session.start) + UpFractalSuffix;
      ObjectCreate(chartId, upFractalName, OBJ_TREND, subWindow, up.time, up.value, session.end, up.value);
      ObjectSetInteger(chartId, upFractalName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(chartId, upFractalName, OBJPROP_COLOR, UpFractalColor);
      ObjectSetString(chartId, upFractalName, OBJPROP_TEXT, UpFractalLabel);

      visuals.isUpFractal = true;
     }

   if(dn.isSet && !visuals.isDnFractal)
     {
      string dnFractalName = ObjPrefix + TimeToString(session.start) + DnFractalSuffix;
      ObjectCreate(chartId, dnFractalName, OBJ_TREND, subWindow, dn.time, dn.value, session.end, dn.value);
      ObjectSetInteger(chartId, dnFractalName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(chartId, dnFractalName, OBJPROP_COLOR, DnFractalColor);
      ObjectSetString(chartId, dnFractalName, OBJPROP_TEXT, DnFractalLabel);

      visuals.isDnFractal = true;
     }
  }

//+------------------------------------------------------------------+
//| Returns if new bar of the fractal timeframe is formed            |
//+------------------------------------------------------------------+
bool IsNewFractalBar()
  {
   datetime curTime = iTime(Symbol(), FractalTimeframe, 0);
   if(curTime != gblLastFractalBar)
     {
      gblLastFractalBar = curTime;
      return true;
     }
   return false;
  }

//+--------------------------------------------------------------------+
//| Returns a Fractal type constructed from the indicator fractal value|
//+--------------------------------------------------------------------+
Fractal GetStrategyFractal(const int &fractalHandle, FractalType fractalType, int shift, ENUM_TIMEFRAMES timeframe, datetime startTime)
  {
   double fractalValue = GetFractal(FractalHandle, fractalType, shift);
   if(fractalValue != EMPTY_VALUE)
     {
      datetime time = iTime(Symbol(), timeframe, shift);
      if(time >= startTime)
        {
         return Fractal(true, fractalValue, time);
        }
     }
   return Fractal();
  }

//+------------------------------------------------------------------+
//| Returns the value of fractal indicator                           |
//+------------------------------------------------------------------+
double GetFractal(const int &fractalHandle, FractalType fractalType, int shift)
  {
   double fractal[];
   if(CopyBuffer(fractalHandle,(int) fractalType,shift,1,fractal) == -1)
      return EMPTY_VALUE;
   return fractal[0];
  }

//+------------------------------------------------------------------+
//| Returns the value of ATR indicator                               |
//+------------------------------------------------------------------+
double GetATR(const int &atrHandle)
  {
   double atr[];
   if(CopyBuffer(atrHandle,0,1,1,atr) == -1)
      return EMPTY_VALUE;
   return atr[0];
  }
//+------------------------------------------------------------------+
