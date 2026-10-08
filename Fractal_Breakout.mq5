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
#include "FractalExport.mqh"

//--- Enums
enum FractalType
  {
   fractal_high = 0,
   fractal_low  = 1
  };

enum DrawdownBasis
  {
   dd_peak_equity = 0,   // From peak equity (all-time)
   dd_daily_loss  = 1    // Loss within the current day
  };

//--- Only the selected method's parameter group is read; optimize one at a time.
enum TrendMethod
  {
   trend_regression = 0,   // Linear regression slope
   trend_efficiency = 1    // Kaufman Efficiency Ratio
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
   bool              isUpFractal;
   bool              isDnFractal;

                     VisualObjects(bool IsUpFractal=false, bool IsDnFractal=false):
                     isUpFractal(IsUpFractal),
                     isDnFractal(IsDnFractal) {}
  };

//--- Input definition
input group    "Trade Parameters"
input double   InpFixedLot                = 0.01;     // Fixed Lot Size
input int      InpAtrPeriod               = 14;       // ATR Period
input int      InpMaxOpenTrades           = 1;        // Max Open Positions (0 = unlimited)
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
input group    "Trend Direction Filter"
input bool     InpUseTrendFilter          = false;    // Use Trend Direction Filter
input TrendMethod InpTrendMethod          = trend_regression; // Trend Method
input group    "Trend: Linear Regression"
input ENUM_TIMEFRAMES InpTrendRegTimeframe = PERIOD_H1; // Regression Timeframe
input int      InpTrendRegBars            = 24;       // Regression Bars N (~1 day on H1)
input double   InpTrendRegMinSlope        = 0.05;     // Min Slope, ATR per bar
input double   InpTrendRegMinR2           = 0.30;     // Min R-squared (0 = off)
input group    "Trend: Efficiency Ratio"
input ENUM_TIMEFRAMES InpTrendErTimeframe = PERIOD_H1; // Efficiency Timeframe
input int      InpTrendErBars             = 24;       // Efficiency Bars N (~1 day on H1)
input double   InpTrendErMinRatio         = 0.30;     // Min Efficiency Ratio (0 - 1)
input group    "Volatility Filter (ATR Ratio)"
input bool     InpUseVolatilityFilter     = false;    // Use Volatility Filter
input ENUM_TIMEFRAMES InpVolAtrTimeframe  = PERIOD_D1; // Volatility ATR Timeframe
input int      InpVolAtrPeriod            = 14;       // Volatility ATR Period
input int      InpVolAtrAvgPeriod         = 20;       // Volatility ATR Average Lookback (bars)
input double   InpVolAtrRatioMin          = 1.0;      // Min ATR Ratio (current / average)
input group    "Session Filter"
input bool     InpUseSessionFilter        = false;    // Master switch: use session filter
input bool     InpEnableASIA              = true;     // Enable ASIA (00:00-08:00 GMT)
input bool     InpEnableLONDON            = true;     // Enable LONDON (08:00-16:00 GMT)
input bool     InpEnableNEWYORK           = true;     // Enable NEWYORK (13:00-21:00 GMT)
input bool     InpSessionUseServerTime    = true;     // Time source: true=server TimeCurrent(), false=TimeGMT()
input group    "Trailing Stop"
input bool     InpUseTrailingStop         = true;     // Use Trailing Stop
input double   InpTrailAtrPercent         = 10;       // Trailing Stop ATR Percent
input bool     InpTrailAfterBreakeven     = true;     // Start Trailing Only After Breakeven
input group    "Breakeven"
input bool     InpUseBreakeven            = false;    // Use Breakeven
input double   InpBreakevenAtrPercent     = 50;       // Trigger: profit as % of ATR
input double   InpBreakevenLockAtrPercent = 5;        // Lock beyond entry, % of ATR (0 = exact)
input group    "Drawdown Guard"
input double   InpMaxDrawdownUSD          = 0;        // Max Drawdown, deposit currency (0 = off)
input DrawdownBasis InpDrawdownBasis      = dd_peak_equity; // Drawdown Basis
input bool     InpDrawdownForceClose      = false;    // Force-close open positions on trip (false = only block new entries)
input group    "Timed Profit Exit"
input bool     InpUseProfitClose          = false;    // Use Timed Profit Exit
input int      InpProfitCloseHour         = 23;       // Sweep From Hour (0 - 23)
input int      InpProfitCloseMin          = 0;        // Sweep From Min (0 - 59)
input double   InpProfitCloseThreshold    = 0;        // Min Profit to Close, gross (0 = any)
input group    "Visual Objects"
input bool     InpShowObjects             = true;     // Draw Visual Objects
input group    "Expert Identification"
input ulong    InpMagicNumber             = 12345;    // Magic Number
input group    "Optimization Criterion"
input int      InpCritMinTrades           = 30;       // Min Trades, reject below (0 = off)
input double   InpCritSigmaCut            = 3.0;      // Outlier Cut in sigmas (0 = off)
input double   InpCritMaxTradeShare       = 0.30;     // Max Share of Profit From One Trade (0 = off)
input double   InpCritMaxDDPercent        = 0;        // Max Equity DD %, reject above (0 = off)

//--- Indicator handles
int AtrHandle;
int FractalHandle;
int AdxHandle;
int VolAtrHandle;
int TrendAtrHandle;

//--- Globals
CTrade Trade;

ENUM_TIMEFRAMES FractalTimeframe = PERIOD_M5;
ENUM_TIMEFRAMES AtrTimeframe     = PERIOD_D1;

string ObjPrefix        = "fractal_breakout_";
string UpFractalSuffix  = "_up_fractal";
string DnFractalSuffix  = "_dn_fractal";
string UpFractalLabel   = "Up Fractal Limit";
string DnFractalLabel   = "Dn Fractal Limit";
color  UpFractalColor   = clrAzure;
color  DnFractalColor   = clrBlanchedAlmond;

Fractal gblUpFractal;
Fractal gblDnFractal;

double gblBuyPeak;
double gblSellTrough;

//--- Drawdown guard. The peak survives midnight so the guard measures true
//--- drawdown; the block flag clears daily so trading can resume next day.
double gblPeakEquity;
double gblDayStartEquity;
bool   gblTradingBlocked;

//--- Trend filter state: +1 up, -1 down, 0 flat (flat blocks both directions).
int      gblTrendDirection;
datetime gblTrendBar;

//--- Latest trend readings, written into the entry comment for analysis.
double   gblTrendSlope;
double   gblTrendR2;
double   gblTrendEr;

//--- Midnight of the day currently being traded; also the cut-off that keeps
//--- yesterday's fractals from carrying over into today.
datetime gblCurrentDay;

datetime gblLastBuyTime;
datetime gblLastSellTime;
datetime gblLastFractalBar;

datetime gblTestStartTime;
datetime gblTestEndTime;

ExpertStats    gblStats;
VisualObjects  gblVisuals;

bool   gblInitOK = false;

//+------------------------------------------------------------------+
//| CSV export. FxColumns() and FxFill() must stay in the same order.|
//+------------------------------------------------------------------+
#define FX_META     3
#define FX_PARAMS   49
#define FX_METRICS  42
#define FX_VALUES   (FX_META + FX_PARAMS + FX_METRICS)

CCSVExporter gExport;

void FxColumns(string &c[])
  {
   ArrayResize(c, 2 + FX_VALUES);
   int i = 0;
   c[i++] = "symbol";
   c[i++] = "timeframe";
   c[i++] = "mode";
   c[i++] = "test_start_ts";
   c[i++] = "test_end_ts";
   c[i++] = "InpFixedLot";
   c[i++] = "InpAtrPeriod";
   c[i++] = "InpMaxOpenTrades";
   c[i++] = "InpAtrPercent";
   c[i++] = "InpTpMultiplier";
   c[i++] = "InpFractalShift";
   c[i++] = "InpUseAdxFilter";
   c[i++] = "InpAdxTimeframe";
   c[i++] = "InpAdxPeriod";
   c[i++] = "InpAdxThreshold";
   c[i++] = "InpAdxUseDirection";
   c[i++] = "InpUseTrendFilter";
   c[i++] = "InpTrendMethod";
   c[i++] = "InpTrendRegTimeframe";
   c[i++] = "InpTrendRegBars";
   c[i++] = "InpTrendRegMinSlope";
   c[i++] = "InpTrendRegMinR2";
   c[i++] = "InpTrendErTimeframe";
   c[i++] = "InpTrendErBars";
   c[i++] = "InpTrendErMinRatio";
   c[i++] = "InpUseVolatilityFilter";
   c[i++] = "InpVolAtrTimeframe";
   c[i++] = "InpVolAtrPeriod";
   c[i++] = "InpVolAtrAvgPeriod";
   c[i++] = "InpVolAtrRatioMin";
   c[i++] = "InpUseSessionFilter";
   c[i++] = "InpEnableASIA";
   c[i++] = "InpEnableLONDON";
   c[i++] = "InpEnableNEWYORK";
   c[i++] = "InpSessionUseServerTime";
   c[i++] = "InpUseTrailingStop";
   c[i++] = "InpTrailAtrPercent";
   c[i++] = "InpTrailAfterBreakeven";
   c[i++] = "InpUseBreakeven";
   c[i++] = "InpBreakevenAtrPercent";
   c[i++] = "InpBreakevenLockAtrPercent";
   c[i++] = "InpMaxDrawdownUSD";
   c[i++] = "InpDrawdownBasis";
   c[i++] = "InpDrawdownForceClose";
   c[i++] = "InpUseProfitClose";
   c[i++] = "InpProfitCloseHour";
   c[i++] = "InpProfitCloseMin";
   c[i++] = "InpProfitCloseThreshold";
   c[i++] = "InpShowObjects";
   c[i++] = "InpMagicNumber";
   c[i++] = "InpCritMinTrades";
   c[i++] = "InpCritSigmaCut";
   c[i++] = "InpCritMaxTradeShare";
   c[i++] = "InpCritMaxDDPercent";
   c[i++] = "initial_deposit";
   c[i++] = "withdrawal";
   c[i++] = "profit";
   c[i++] = "gross_profit";
   c[i++] = "gross_loss";
   c[i++] = "profit_factor";
   c[i++] = "expected_payoff";
   c[i++] = "recovery_factor";
   c[i++] = "sharpe";
   c[i++] = "min_margin_level";
   c[i++] = "complex_criterion";
   c[i++] = "deals";
   c[i++] = "trades";
   c[i++] = "profit_trades";
   c[i++] = "loss_trades";
   c[i++] = "short_trades";
   c[i++] = "long_trades";
   c[i++] = "profit_short_trades";
   c[i++] = "profit_long_trades";
   c[i++] = "balance_min";
   c[i++] = "balance_dd";
   c[i++] = "balance_dd_pct_abs";
   c[i++] = "balance_dd_relative";
   c[i++] = "balance_dd_pct";
   c[i++] = "equity_min";
   c[i++] = "equity_dd";
   c[i++] = "equity_dd_pct_abs";
   c[i++] = "equity_dd_relative";
   c[i++] = "equity_dd_pct";
   c[i++] = "max_profit_trade";
   c[i++] = "max_loss_trade";
   c[i++] = "con_profit_max";
   c[i++] = "con_profit_max_trades";
   c[i++] = "max_con_wins";
   c[i++] = "max_con_profit_trades";
   c[i++] = "con_loss_max";
   c[i++] = "con_loss_max_trades";
   c[i++] = "max_con_losses";
   c[i++] = "max_con_loss_trades";
   c[i++] = "avg_con_wins";
   c[i++] = "avg_con_losses";
   c[i++] = "custom";
  }

//--- mode: 0 = optimisation pass, 1 = single run
void FxFill(double &d[], const double custom)
  {
   ArrayResize(d, FX_VALUES);
   int i = 0;
   d[i++] = MQLInfoInteger(MQL_OPTIMIZATION) ? 0.0 : 1.0;
   d[i++] = (double)gblTestStartTime;
   d[i++] = (double)TimeCurrent();
   d[i++] = (double)InpFixedLot;
   d[i++] = (double)InpAtrPeriod;
   d[i++] = (double)InpMaxOpenTrades;
   d[i++] = (double)InpAtrPercent;
   d[i++] = (double)InpTpMultiplier;
   d[i++] = (double)InpFractalShift;
   d[i++] = (double)InpUseAdxFilter;
   d[i++] = (double)InpAdxTimeframe;
   d[i++] = (double)InpAdxPeriod;
   d[i++] = (double)InpAdxThreshold;
   d[i++] = (double)InpAdxUseDirection;
   d[i++] = (double)InpUseTrendFilter;
   d[i++] = (double)InpTrendMethod;
   d[i++] = (double)InpTrendRegTimeframe;
   d[i++] = (double)InpTrendRegBars;
   d[i++] = (double)InpTrendRegMinSlope;
   d[i++] = (double)InpTrendRegMinR2;
   d[i++] = (double)InpTrendErTimeframe;
   d[i++] = (double)InpTrendErBars;
   d[i++] = (double)InpTrendErMinRatio;
   d[i++] = (double)InpUseVolatilityFilter;
   d[i++] = (double)InpVolAtrTimeframe;
   d[i++] = (double)InpVolAtrPeriod;
   d[i++] = (double)InpVolAtrAvgPeriod;
   d[i++] = (double)InpVolAtrRatioMin;
   d[i++] = (double)InpUseSessionFilter;
   d[i++] = (double)InpEnableASIA;
   d[i++] = (double)InpEnableLONDON;
   d[i++] = (double)InpEnableNEWYORK;
   d[i++] = (double)InpSessionUseServerTime;
   d[i++] = (double)InpUseTrailingStop;
   d[i++] = (double)InpTrailAtrPercent;
   d[i++] = (double)InpTrailAfterBreakeven;
   d[i++] = (double)InpUseBreakeven;
   d[i++] = (double)InpBreakevenAtrPercent;
   d[i++] = (double)InpBreakevenLockAtrPercent;
   d[i++] = (double)InpMaxDrawdownUSD;
   d[i++] = (double)InpDrawdownBasis;
   d[i++] = (double)InpDrawdownForceClose;
   d[i++] = (double)InpUseProfitClose;
   d[i++] = (double)InpProfitCloseHour;
   d[i++] = (double)InpProfitCloseMin;
   d[i++] = (double)InpProfitCloseThreshold;
   d[i++] = (double)InpShowObjects;
   d[i++] = (double)InpMagicNumber;
   d[i++] = (double)InpCritMinTrades;
   d[i++] = (double)InpCritSigmaCut;
   d[i++] = (double)InpCritMaxTradeShare;
   d[i++] = (double)InpCritMaxDDPercent;
   d[i++] = TesterStatistics(STAT_INITIAL_DEPOSIT);
   d[i++] = TesterStatistics(STAT_WITHDRAWAL);
   d[i++] = TesterStatistics(STAT_PROFIT);
   d[i++] = TesterStatistics(STAT_GROSS_PROFIT);
   d[i++] = TesterStatistics(STAT_GROSS_LOSS);
   d[i++] = TesterStatistics(STAT_PROFIT_FACTOR);
   d[i++] = TesterStatistics(STAT_EXPECTED_PAYOFF);
   d[i++] = TesterStatistics(STAT_RECOVERY_FACTOR);
   d[i++] = TesterStatistics(STAT_SHARPE_RATIO);
   d[i++] = TesterStatistics(STAT_MIN_MARGINLEVEL);
   d[i++] = TesterStatistics(STAT_COMPLEX_CRITERION);
   d[i++] = TesterStatistics(STAT_DEALS);
   d[i++] = TesterStatistics(STAT_TRADES);
   d[i++] = TesterStatistics(STAT_PROFIT_TRADES);
   d[i++] = TesterStatistics(STAT_LOSS_TRADES);
   d[i++] = TesterStatistics(STAT_SHORT_TRADES);
   d[i++] = TesterStatistics(STAT_LONG_TRADES);
   d[i++] = TesterStatistics(STAT_PROFIT_SHORTTRADES);
   d[i++] = TesterStatistics(STAT_PROFIT_LONGTRADES);
   d[i++] = TesterStatistics(STAT_BALANCEMIN);
   d[i++] = TesterStatistics(STAT_BALANCE_DD);
   d[i++] = TesterStatistics(STAT_BALANCEDD_PERCENT);
   d[i++] = TesterStatistics(STAT_BALANCE_DD_RELATIVE);
   d[i++] = TesterStatistics(STAT_BALANCE_DDREL_PERCENT);
   d[i++] = TesterStatistics(STAT_EQUITYMIN);
   d[i++] = TesterStatistics(STAT_EQUITY_DD);
   d[i++] = TesterStatistics(STAT_EQUITYDD_PERCENT);
   d[i++] = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
   d[i++] = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   d[i++] = TesterStatistics(STAT_MAX_PROFITTRADE);
   d[i++] = TesterStatistics(STAT_MAX_LOSSTRADE);
   d[i++] = TesterStatistics(STAT_CONPROFITMAX);
   d[i++] = TesterStatistics(STAT_CONPROFITMAX_TRADES);
   d[i++] = TesterStatistics(STAT_MAX_CONWINS);
   d[i++] = TesterStatistics(STAT_MAX_CONPROFIT_TRADES);
   d[i++] = TesterStatistics(STAT_CONLOSSMAX);
   d[i++] = TesterStatistics(STAT_CONLOSSMAX_TRADES);
   d[i++] = TesterStatistics(STAT_MAX_CONLOSSES);
   d[i++] = TesterStatistics(STAT_MAX_CONLOSS_TRADES);
   d[i++] = TesterStatistics(STAT_PROFITTRADES_AVGCON);
   d[i++] = TesterStatistics(STAT_LOSSTRADES_AVGCON);
   d[i++] = custom;
  }

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

   if(InpMaxOpenTrades < 0)
     {
      Print("Please enter max open positions of 0 or above (0 = unlimited)");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpMaxDrawdownUSD < 0)
     {
      Print("Please enter max drawdown of 0 or above (0 = guard disabled)");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseProfitClose &&
      (InpProfitCloseHour < 0 || InpProfitCloseHour > 23 ||
       InpProfitCloseMin  < 0 || InpProfitCloseMin  > 59))
     {
      Print("Timed profit exit: hour must be within 0..23 and minute within 0..59");
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

   if(InpUseTrendFilter && InpTrendMethod == trend_regression &&
      (InpTrendRegBars < 3 || InpTrendRegMinSlope < 0 ||
       InpTrendRegMinR2 < 0 || InpTrendRegMinR2 > 1))
     {
      Print("Regression trend filter: need bars >= 3, min slope >= 0, R-squared within 0..1");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseTrendFilter && InpTrendMethod == trend_efficiency &&
      (InpTrendErBars < 3 || InpTrendErMinRatio < 0 || InpTrendErMinRatio > 1))
     {
      Print("Efficiency trend filter: need bars >= 3 and ratio within 0..1");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseVolatilityFilter && (InpVolAtrPeriod <= 0 || InpVolAtrAvgPeriod <= 0 || InpVolAtrRatioMin <= 0))
     {
      Print("Please enter volatility ATR period, average lookback and ratio above 0");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUseSessionFilter && !InpEnableASIA && !InpEnableLONDON &&
      !InpEnableNEWYORK)
     {
      Print("Session filter is on but every session is disabled - no entries would be possible");
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

//--- Regression normalises its slope by ATR of the same timeframe it measures
   TrendAtrHandle = INVALID_HANDLE;
   if(InpUseTrendFilter && InpTrendMethod == trend_regression)
     {
      TrendAtrHandle = iATR(Symbol(), InpTrendRegTimeframe, InpAtrPeriod);
      if(TrendAtrHandle == INVALID_HANDLE)
        {
         Print("Failed to create trend ATR handle");
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

   if(InpUseTrailingStop && InpTrailAfterBreakeven && !InpUseBreakeven)
      Print("WARNING: trailing waits for breakeven, but breakeven is off - trailing will never start");

   gblInitOK = true;

//--- CSV export stream: one file per run mode, shared by all agents
   string csvCols[];
   FxColumns(csvCols);
   string csvName = MQLInfoInteger(MQL_OPTIMIZATION) ? "Fractal_OPT.csv" : "Fractal_OOS.csv";
   if(!gExport.Open(csvName, csvCols))
      Print("FractalExport: stream unavailable - rows will NOT be saved");

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
   if(VolAtrHandle   != INVALID_HANDLE)
      IndicatorRelease(VolAtrHandle);
   if(TrendAtrHandle != INVALID_HANDLE)
      IndicatorRelease(TrendAtrHandle);

//--- Delete visual objects
   ObjectsDeleteAll(ChartID(), ObjPrefix);

//--- Print strategy stats
   if(gblInitOK)
     {
      PrintStats();
     }

   gExport.Close();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Roll over per-day state at midnight
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   if(gblCurrentDay != today)
     {
      InitGlobals();
      gblCurrentDay     = today;
      gblDayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
     }

//--- Drawdown guard
   if(InpMaxDrawdownUSD > 0)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > gblPeakEquity)
         gblPeakEquity = equity;

      if(!gblTradingBlocked)
        {
         double drawdown = (InpDrawdownBasis == dd_peak_equity)
                           ? gblPeakEquity     - equity
                           : gblDayStartEquity - equity;
         if(drawdown >= InpMaxDrawdownUSD)
           {
            gblTradingBlocked = true;
            PrintFormat("Drawdown guard tripped: %.2f >= %.2f. New entries blocked until midnight.",
                        drawdown, InpMaxDrawdownUSD);
            if(InpDrawdownForceClose)
               CloseAllPositions();
           }
        }
     }

//--- Refresh the trend direction (no-op until the trend timeframe closes a bar)
   UpdateTrendDirection();

//--- Set fractal values
   bool newFractalBar = IsNewFractalBar();
   if(newFractalBar)
     {
      if(!gblUpFractal.isSet)
        {
         gblUpFractal = GetStrategyFractal(FractalHandle, fractal_high, InpFractalShift, FractalTimeframe, gblCurrentDay);
        }

      if(!gblDnFractal.isSet)
        {
         gblDnFractal = GetStrategyFractal(FractalHandle, fractal_low, InpFractalShift, FractalTimeframe, gblCurrentDay);
        }
     }

//--- Open position on fractal breakout
   MqlTick curTick;
   if(!SymbolInfoTick(Symbol(), curTick))
      return;

//--- Protect a position that has run far enough in our favour
   ManageBreakeven();

//--- Update trailing stop
   if(InpUseTrailingStop)
     {
      UpdateTrailExtremes(curTick);
      if(newFractalBar)
         ManageTrailingStops();
     }

//--- Sweep profitable positions once the configured time of day is reached
   CloseProfitablePositions();

   if(!gblTradingBlocked && gblUpFractal.isSet)
     {
      if(curTick.bid >= gblUpFractal.value)
        {
         if(OpenSlotAvailable() &&
            CheckAdxFilter(true) && CheckTrendFilter(true) && CheckVolatilityFilter() &&
            CheckSessionFilter())
           {
            if(OpenTrade(POSITION_TYPE_BUY, curTick))
              {
               gblLastBuyTime = TimeCurrent();
               //--- Drop the fractal: the next entry must wait for a fresh breakout
               gblUpFractal = Fractal();
               gblVisuals.isUpFractal = false;
               Print("Buy trade taken at ", gblLastBuyTime);
              }
           }
        }
     }

   if(!gblTradingBlocked && gblDnFractal.isSet)
     {
      if(curTick.bid <= gblDnFractal.value)
        {
         if(OpenSlotAvailable() &&
            CheckAdxFilter(false) && CheckTrendFilter(false) && CheckVolatilityFilter() &&
            CheckSessionFilter())
           {
            if(OpenTrade(POSITION_TYPE_SELL, curTick))
              {
               gblLastSellTime = TimeCurrent();
               //--- Drop the fractal: the next entry must wait for a fresh breakout
               gblDnFractal = Fractal();
               gblVisuals.isDnFractal = false;
               Print("Sell trade taken at ", gblLastSellTime);
              }
           }
        }
     }

//--- Draw graphical objects
   if(InpShowObjects)
      DrawVisualObjects(gblCurrentDay, gblUpFractal, gblDnFractal, gblVisuals);
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

         if(!Trade.Buy(lots, Symbol(), curTick.ask, sl, tp, TrendComment()))
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

         if(!Trade.Sell(lots, Symbol(), curTick.bid, sl, tp, TrendComment()))
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
//| Trend direction by least-squares slope over closed bars 1..N.    |
//| The slope is normalised by ATR of the same timeframe so the      |
//| threshold stays comparable across price levels.                  |
//+------------------------------------------------------------------+
bool TrendByRegression(int &direction)
  {
   int n = InpTrendRegBars;
   double close[];
//--- Oldest first, so a rising series gives a positive slope
   ArraySetAsSeries(close, false);
   if(CopyClose(Symbol(), InpTrendRegTimeframe, 1, n, close) < n)
      return false;

   double atr[];
   if(CopyBuffer(TrendAtrHandle, 0, 1, 1, atr) <= 0 || atr[0] <= 0)
      return false;

   double sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
   for(int i = 0; i < n; i++)
     {
      sumX  += i;
      sumY  += close[i];
      sumXY += i * close[i];
      sumXX += (double)i * i;
     }

   double denom = n * sumXX - sumX * sumX;
   if(denom == 0)
      return false;

   double slope     = (n * sumXY - sumX * sumY) / denom;
   double intercept = (sumY - slope * sumX) / n;

   double meanY = sumY / n;
   double ssTot = 0, ssRes = 0;
   for(int i = 0; i < n; i++)
     {
      double fit = intercept + slope * i;
      ssTot += (close[i] - meanY) * (close[i] - meanY);
      ssRes += (close[i] - fit)   * (close[i] - fit);
     }
   double r2 = (ssTot > 0) ? 1.0 - ssRes / ssTot : 0.0;

   double slopeAtr = slope / atr[0];

   gblTrendSlope = slopeAtr;
   gblTrendR2    = r2;

   direction = 0;
   if(MathAbs(slopeAtr) >= InpTrendRegMinSlope && r2 >= InpTrendRegMinR2)
      direction = (slopeAtr > 0) ? 1 : -1;
   return true;
  }

//+------------------------------------------------------------------+
//| Trend direction by Kaufman Efficiency Ratio over closed bars     |
//| 1..N: net move divided by the total path walked. 1 is a clean    |
//| run, 0 is chop. Direction comes from the sign of the net move.   |
//+------------------------------------------------------------------+
bool TrendByEfficiency(int &direction)
  {
   int n = InpTrendErBars;
   double close[];
//--- Oldest first, so a rising series gives a positive net move
   ArraySetAsSeries(close, false);
   if(CopyClose(Symbol(), InpTrendErTimeframe, 1, n, close) < n)
      return false;

   double net  = close[n-1] - close[0];
   double path = 0;
   for(int i = 1; i < n; i++)
      path += MathAbs(close[i] - close[i-1]);

   if(path <= 0)
      return false;

   double ratio = MathAbs(net) / path;

   gblTrendEr = ratio;

   direction = 0;
   if(ratio >= InpTrendErMinRatio)
      direction = (net > 0) ? 1 : -1;
   return true;
  }

//+------------------------------------------------------------------+
//| Recomputes the trend direction once per bar of the trend         |
//| timeframe. Missing data leaves the reading flat, which blocks    |
//| both sides rather than guessing a direction.                     |
//+------------------------------------------------------------------+
void UpdateTrendDirection()
  {
   if(!InpUseTrendFilter)
      return;

   ENUM_TIMEFRAMES tf = (InpTrendMethod == trend_regression)
                        ? InpTrendRegTimeframe : InpTrendErTimeframe;
   datetime bar = iTime(Symbol(), tf, 0);
   if(bar == gblTrendBar)
      return;

   int  dir = 0;
   bool ok  = (InpTrendMethod == trend_regression)
              ? TrendByRegression(dir)
              : TrendByEfficiency(dir);

   gblTrendDirection = ok ? dir : 0;
   gblTrendBar       = bar;

   if(!ok)
     {
      gblTrendSlope = 0;
      gblTrendR2    = 0;
      gblTrendEr    = 0;
     }
  }

//+------------------------------------------------------------------+
//| Entry comment with the current trend reading (MT5 limit: 31 chars)|
//| RG = regression: direction, slope in ATR/bar, R-squared          |
//| ER = efficiency: direction, efficiency ratio                     |
//+------------------------------------------------------------------+
string TrendComment()
  {
   if(!InpUseTrendFilter)
      return "";
   if(InpTrendMethod == trend_regression)
      return StringFormat("RG d%+d s%.3f r%.2f", gblTrendDirection, gblTrendSlope, gblTrendR2);
   return StringFormat("ER d%+d e%.2f", gblTrendDirection, gblTrendEr);
  }

//+------------------------------------------------------------------+
//| Trend Filter: entries are allowed only along an established      |
//| trend; a flat reading blocks both directions                     |
//+------------------------------------------------------------------+
bool CheckTrendFilter(bool isBuy)
  {
   if(!InpUseTrendFilter)
      return true;
   if(gblTrendDirection == 0)
      return false;
   return isBuy ? (gblTrendDirection > 0) : (gblTrendDirection < 0);
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
//| Session Filter: entry is allowed inside any enabled session      |
//+------------------------------------------------------------------+
bool CheckSessionFilter()
  {
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime dt;
   if(InpSessionUseServerTime)
      TimeToStruct(TimeCurrent(), dt);
   else
      TimeToStruct(TimeGMT(), dt);
   int minutes = dt.hour * 60 + dt.min;

   if(InpEnableASIA    && minutes >=  0      && minutes <  8 * 60) return true;
   if(InpEnableLONDON  && minutes >=  8 * 60 && minutes < 16 * 60) return true;
   if(InpEnableNEWYORK && minutes >= 13 * 60 && minutes < 21 * 60) return true;
   return false;
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
   gblTradingBlocked = false;
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
//| Breakeven: once a position is far enough in profit, pull the stop|
//| up to entry (plus an optional lock) so it can no longer lose.    |
//| Only ever improves the stop, so it cannot fight the trailing.    |
//+------------------------------------------------------------------+
void ManageBreakeven()
  {
   if(!InpUseBreakeven)
      return;

   double atr = GetATR(AtrHandle);
   if(atr == EMPTY_VALUE || atr <= 0)
      return;

   double trigger = InpBreakevenAtrPercent / 100 * atr;
   double lock    = InpBreakevenLockAtrPercent / 100 * atr;
   if(trigger <= 0)
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

      double openPrice = posInfo.PriceOpen();
      double curSl     = posInfo.StopLoss();

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
        {
         if(curTick.bid - openPrice < trigger)
            continue;
         double newSl = openPrice + lock;
         if(curSl != 0 && newSl - curSl < tickSize)
            continue;
         if(!CheckStopsLevel(curTick.bid - newSl) || !CheckFreezeLevel(curTick.bid - newSl))
            continue;
         if(Trade.PositionModify(posInfo.Ticket(), newSl, posInfo.TakeProfit()))
            Print("Breakeven SL set for buy position: ", posInfo.Ticket(), " -> ", newSl);
        }
      else
         if(posInfo.PositionType() == POSITION_TYPE_SELL)
           {
            if(openPrice - curTick.ask < trigger)
               continue;
            double newSl = openPrice - lock;
            if(curSl != 0 && curSl - newSl < tickSize)
               continue;
            if(!CheckStopsLevel(newSl - curTick.ask) || !CheckFreezeLevel(newSl - curTick.ask))
               continue;
            if(Trade.PositionModify(posInfo.Ticket(), newSl, posInfo.TakeProfit()))
               Print("Breakeven SL set for sell position: ", posInfo.Ticket(), " -> ", newSl);
           }
     }
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
         double curSl = posInfo.StopLoss();

         //--- A stop at or past entry means breakeven has already fired
         if(InpTrailAfterBreakeven && (curSl == 0 || curSl < posInfo.PriceOpen()))
            continue;

         double newSl = gblBuyPeak - trailDist;
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
            double curSl = posInfo.StopLoss();

            //--- A stop at or past entry means breakeven has already fired
            if(InpTrailAfterBreakeven && (curSl == 0 || curSl > posInfo.PriceOpen()))
               continue;

            double newSl = gblSellTrough + trailDist;
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
//| True when this EA may open one more position on this symbol      |
//+------------------------------------------------------------------+
bool OpenSlotAvailable()
  {
   if(InpMaxOpenTrades == 0)
      return true;

   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      CPositionInfo posInfo;
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() == Symbol() && posInfo.Magic() == InpMagicNumber)
         count++;
     }
   return count < InpMaxOpenTrades;
  }

//+------------------------------------------------------------------+
//| Timed Profit Exit: from the configured time until midnight, close |
//| any position of this EA whose profit clears the threshold. Swap   |
//| and commission are deliberately excluded from that profit.        |
//+------------------------------------------------------------------+
void CloseProfitablePositions()
  {
   if(!InpUseProfitClose)
      return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour * 60 + dt.min < InpProfitCloseHour * 60 + InpProfitCloseMin)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      CPositionInfo posInfo;
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != InpMagicNumber)
         continue;
      if(posInfo.Profit() <= InpProfitCloseThreshold)
         continue;

      if(Trade.PositionClose(posInfo.Ticket()))
         PrintFormat("Timed profit exit: closed #%I64u at %.2f", posInfo.Ticket(), posInfo.Profit());
      else
         Print("Timed profit exit failed for ", posInfo.Ticket(), ": ", Trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Drawdown guard escalation: closes every open position of this EA |
//| on this symbol, regardless of profit, instead of just waiting    |
//| for new entries to stay blocked.                                  |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      CPositionInfo posInfo;
      if(!posInfo.SelectByIndex(i))
         continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != InpMagicNumber)
         continue;

      if(Trade.PositionClose(posInfo.Ticket()))
         PrintFormat("Drawdown guard: force-closed #%I64u at %.2f", posInfo.Ticket(), posInfo.Profit());
      else
         Print("Drawdown guard: force-close failed for ", posInfo.Ticket(), ": ", Trade.ResultRetcodeDescription());
     }
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
void DrawVisualObjects(datetime dayStart, const Fractal &up, const Fractal &dn, VisualObjects &visuals)
  {
   long     chartId   = ChartID();
   int      subWindow = 0;
   datetime dayEnd    = dayStart + 86400;

   if(up.isSet && !visuals.isUpFractal)
     {
      string upFractalName = ObjPrefix + TimeToString(up.time) + UpFractalSuffix;
      ObjectCreate(chartId, upFractalName, OBJ_TREND, subWindow, up.time, up.value, dayEnd, up.value);
      ObjectSetInteger(chartId, upFractalName, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(chartId, upFractalName, OBJPROP_COLOR, UpFractalColor);
      ObjectSetString(chartId, upFractalName, OBJPROP_TEXT, UpFractalLabel);

      visuals.isUpFractal = true;
     }

   if(dn.isSet && !visuals.isDnFractal)
     {
      string dnFractalName = ObjPrefix + TimeToString(dn.time) + DnFractalSuffix;
      ObjectCreate(chartId, dnFractalName, OBJ_TREND, subWindow, dn.time, dn.value, dayEnd, dn.value);
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
//| Net profit with outlier trades removed: anything above           |
//| mean + N*sigma is dropped, so a pass cannot win on a couple of    |
//| lucky trades. Falls back to the plain figure when disabled or     |
//| when the sample is too small to estimate sigma.                   |
//+------------------------------------------------------------------+
double TrimmedProfit()
  {
   if(InpCritSigmaCut <= 0)
      return TesterStatistics(STAT_PROFIT);

   if(!HistorySelect(0, TimeCurrent()))
      return TesterStatistics(STAT_PROFIT);

   int total = HistoryDealsTotal();
   double results[];
   ArrayResize(results, total);

   int n = 0;
   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT)
         continue;
      results[n++] = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                   + HistoryDealGetDouble(ticket, DEAL_SWAP)
                   + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
     }

   if(n < 2)
      return TesterStatistics(STAT_PROFIT);

   double sum = 0;
   for(int i = 0; i < n; i++)
      sum += results[i];
   double mean = sum / n;

   double variance = 0;
   for(int i = 0; i < n; i++)
      variance += (results[i] - mean) * (results[i] - mean);
   double sigma = MathSqrt(variance / n);

   double cutoff  = mean + InpCritSigmaCut * sigma;
   double trimmed = 0;
   for(int i = 0; i < n; i++)
      if(results[i] <= cutoff)
         trimmed += results[i];

   return trimmed;
  }

//+------------------------------------------------------------------+
//| Custom optimization criterion. Set OptimizationCriterion=6        |
//| (Custom max) in the tester for this to drive pass ranking.        |
//| Gates return 0; everything else stays continuous so the genetic   |
//| algorithm keeps a gradient to climb.                              |
//+------------------------------------------------------------------+
double FxCriterion()
  {
   int trades = (int)TesterStatistics(STAT_TRADES);
   if(InpCritMinTrades > 0 && trades < InpCritMinTrades)
      return 0.0;

   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(InpCritMaxDDPercent > 0 && drawdown > InpCritMaxDDPercent)
      return 0.0;

   double rawProfit = TesterStatistics(STAT_PROFIT);
   if(rawProfit <= 0)
      return 0.0;

//--- Reject a pass carried by a single trade
   if(InpCritMaxTradeShare > 0 &&
      TesterStatistics(STAT_MAX_PROFITTRADE) / rawProfit > InpCritMaxTradeShare)
      return 0.0;

   double profit = TrimmedProfit();
   if(profit <= 0)
      return 0.0;

//--- Significance grows with the square root of the sample, not linearly
   if(drawdown <= 0)
      drawdown = 0.01;
   return (profit / drawdown) * MathSqrt((double)trades);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| CSV export. FxColumns() and FxFill() must stay in the same order. |

//+------------------------------------------------------------------+
//| Scores the pass, then hands the row to the exporter.             |
//+------------------------------------------------------------------+
double OnTester()
  {
   double score = FxCriterion();

   double data[];
   FxFill(data, score);

   string prefix[2];
   prefix[0] = _Symbol;
   prefix[1] = EnumToString((ENUM_TIMEFRAMES)Period());

   gExport.WriteRow(prefix, data);

   return score;
  }
