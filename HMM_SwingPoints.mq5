//+------------------------------------------------------------------+
//|                                              HMM_SwingPoints.mq5 |
//|   Gaussian HMM Swing Point Detector                              |
//|   Detects market turning points using HMM state transitions      |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots   2
#property indicator_buffers 2

#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "Swing Low"

#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label2  "Swing High"

//---------------------------- SETTINGS ------------------------------//
#define MAX_T       1000          // max training length (bars)
#define MAX_STATES  3             // hard cap on HMM states
#define NEG_INF     -1e100        // log(0) sentinel

input int    InpStates       = 2;       // Number of HMM states (usually 2)
input int    InpTrainLen     = 300;     // Max bars used for training (<= MAX_T)
input int    InpMaxIter      = 10;      // Baum–Welch iterations
input double InpMinSigma2    = 1e-6;    // Min variance to avoid degenerate Gaussians
input double InpMinProb      = 1e-8;    // Min probability (for logs)
input int    InpLookback     = 3;       // Bars to confirm swing point
input bool   InpShowOnTransition = true; // Mark swing on state transition

//------------------------ INDICATOR BUFFERS -------------------------//
double SwingLowBuffer[];    // Up arrows for swing lows (buy signals)
double SwingHighBuffer[];   // Down arrows for swing highs (sell signals)

//--------------------- HMM GLOBAL ARRAYS ----------------------------//
double obs[MAX_T];
double piArr[MAX_STATES];
double A[MAX_STATES][MAX_STATES];
double mu[MAX_STATES];
double sigma2[MAX_STATES];
double logAlpha[MAX_T][MAX_STATES];
double logBeta[MAX_T][MAX_STATES];
double gammaArr[MAX_T][MAX_STATES];
double logDelta[MAX_T][MAX_STATES];
int    psiArr[MAX_T][MAX_STATES];
int    path[MAX_T];

//+------------------------------------------------------------------+
//| Helper: log-sum-exp                                              |
//+------------------------------------------------------------------+
double LogSumExp(double a, double b)
{
   if(a <= NEG_INF) return b;
   if(b <= NEG_INF) return a;
   double m = (a > b ? a : b);
   return m + MathLog(MathExp(a - m) + MathExp(b - m));
}

//+------------------------------------------------------------------+
//| Gaussian log emission                                            |
//+------------------------------------------------------------------+
double LogEmissionProb(const int state, const double o)
{
   double v = sigma2[state];
   if(v < InpMinSigma2) v = InpMinSigma2;
   double diff = o - mu[state];
   return -0.5 * diff * diff / v;
}

//+------------------------------------------------------------------+
//| Initialize HMM parameters                                        |
//+------------------------------------------------------------------+
void InitializeHMM(const int NStates, const int T)
{
   double mean = 0.0;
   for(int t = 0; t < T; t++)
      mean += obs[t];
   mean /= (double)T;

   double var = 0.0;
   for(int t = 0; t < T; t++)
   {
      double d = obs[t] - mean;
      var += d * d;
   }
   var /= (double)T;
   if(var < InpMinSigma2) var = InpMinSigma2;

   for(int i = 0; i < NStates; i++)
      piArr[i] = 1.0 / (double)NStates;

   for(int i = 0; i < NStates; i++)
      for(int j = 0; j < NStates; j++)
         A[i][j] = 1.0 / (double)NStates;

   double step = (NStates > 1 ? 1.0 / (double)(NStates - 1) : 0.0);
   double sdev = MathSqrt(var);
   for(int i = 0; i < NStates; i++)
   {
      double offset = (step * i - 0.5) * sdev;
      mu[i]      = mean + offset;
      sigma2[i]  = var;
   }
}

//+------------------------------------------------------------------+
//| Baum–Welch training                                              |
//+------------------------------------------------------------------+
void BaumWelchTrain(const int NStates, const int T, const int maxIter)
{
   for(int iter = 0; iter < maxIter; iter++)
   {
      // Forward
      for(int i = 0; i < NStates; i++)
      {
         double p = piArr[i];
         if(p < InpMinProb) p = InpMinProb;
         logAlpha[0][i] = MathLog(p) + LogEmissionProb(i, obs[0]);
      }

      for(int t = 1; t < T; t++)
      {
         for(int j = 0; j < NStates; j++)
         {
            double ls = NEG_INF;
            for(int i = 0; i < NStates; i++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double cand = logAlpha[t - 1][i] + MathLog(a);
               ls = LogSumExp(ls, cand);
            }
            logAlpha[t][j] = ls + LogEmissionProb(j, obs[t]);
         }
      }

      // Backward
      for(int i = 0; i < NStates; i++)
         logBeta[T - 1][i] = 0.0;

      for(int t = T - 2; t >= 0; t--)
      {
         for(int i = 0; i < NStates; i++)
         {
            double ls = NEG_INF;
            for(int j = 0; j < NStates; j++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double cand = MathLog(a) + LogEmissionProb(j, obs[t + 1]) + logBeta[t + 1][j];
               ls = LogSumExp(ls, cand);
            }
            logBeta[t][i] = ls;
         }
      }

      // Gamma & Xi
      double denomA[MAX_STATES];
      double numerA[MAX_STATES][MAX_STATES];

      for(int i = 0; i < NStates; i++)
      {
         denomA[i] = 0.0;
         for(int j = 0; j < NStates; j++)
            numerA[i][j] = 0.0;
      }

      for(int t = 0; t < T; t++)
      {
         double logDenom = NEG_INF;
         for(int i = 0; i < NStates; i++)
         {
            double v = logAlpha[t][i] + logBeta[t][i];
            logDenom = LogSumExp(logDenom, v);
         }

         for(int i = 0; i < NStates; i++)
         {
            double v = logAlpha[t][i] + logBeta[t][i] - logDenom;
            gammaArr[t][i] = MathExp(v);
            if(gammaArr[t][i] < InpMinProb) gammaArr[t][i] = InpMinProb;
         }
      }

      for(int t = 0; t < T - 1; t++)
      {
         double logDenomXi = NEG_INF;
         for(int i = 0; i < NStates; i++)
         {
            for(int j = 0; j < NStates; j++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double logTerm = logAlpha[t][i] + MathLog(a) + LogEmissionProb(j, obs[t + 1]) + logBeta[t + 1][j];
               logDenomXi = LogSumExp(logDenomXi, logTerm);
            }
         }

         for(int i = 0; i < NStates; i++)
         {
            double gamma_t_i = 0.0;
            for(int j = 0; j < NStates; j++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double logNumer = logAlpha[t][i] + MathLog(a) + LogEmissionProb(j, obs[t + 1]) + logBeta[t + 1][j];
               double xi_t_ij = MathExp(logNumer - logDenomXi);
               if(xi_t_ij < InpMinProb) xi_t_ij = InpMinProb;
               numerA[i][j] += xi_t_ij;
               gamma_t_i    += xi_t_ij;
            }
            denomA[i] += gamma_t_i;
         }
      }

      // Update π
      for(int i = 0; i < NStates; i++)
         piArr[i] = gammaArr[0][i];

      // Update A
      for(int i = 0; i < NStates; i++)
      {
         double denom = denomA[i];
         if(denom <= 0.0) denom = 1e-12;
         double rowsum = 0.0;
         for(int j = 0; j < NStates; j++)
         {
            double v = numerA[i][j] / denom;
            if(v < InpMinProb) v = InpMinProb;
            A[i][j] = v;
            rowsum += v;
         }
         if(rowsum > 0.0)
         {
            for(int j = 0; j < NStates; j++)
               A[i][j] /= rowsum;
         }
      }

      // Update μ & σ²
      for(int i = 0; i < NStates; i++)
      {
         double gsum  = 0.0;
         double gObs  = 0.0;
         double gObs2 = 0.0;
         for(int t = 0; t < T; t++)
         {
            double g = gammaArr[t][i];
            gsum  += g;
            gObs  += g * obs[t];
            gObs2 += g * obs[t] * obs[t];
         }
         if(gsum <= 0.0) gsum = 1e-12;
         mu[i] = gObs / gsum;
         double m2 = gObs2 / gsum;
         sigma2[i] = m2 - mu[i] * mu[i];
         if(sigma2[i] < InpMinSigma2) sigma2[i] = InpMinSigma2;
      }
   }
}

//+------------------------------------------------------------------+
//| Viterbi decoding                                                 |
//+------------------------------------------------------------------+
void ViterbiDecode(const int NStates, const int T)
{
   for(int i = 0; i < NStates; i++)
   {
      double p = piArr[i];
      if(p < InpMinProb) p = InpMinProb;
      logDelta[0][i] = MathLog(p) + LogEmissionProb(i, obs[0]);
      psiArr[0][i]   = 0;
   }

   for(int t = 1; t < T; t++)
   {
      for(int j = 0; j < NStates; j++)
      {
         double bestVal   = NEG_INF;
         int    bestState = 0;
         for(int i = 0; i < NStates; i++)
         {
            double a = A[i][j];
            if(a < InpMinProb) a = InpMinProb;
            double val = logDelta[t - 1][i] + MathLog(a);
            if(val > bestVal)
            {
               bestVal   = val;
               bestState = i;
            }
         }
         logDelta[t][j] = bestVal + LogEmissionProb(j, obs[t]);
         psiArr[t][j]   = bestState;
      }
   }

   double bestVal   = NEG_INF;
   int    bestState = 0;
   for(int i = 0; i < NStates; i++)
   {
      if(logDelta[T - 1][i] > bestVal)
      {
         bestVal   = logDelta[T - 1][i];
         bestState = i;
      }
   }

   path[T - 1] = bestState;
   for(int t = T - 2; t >= 0; t--)
      path[t] = psiArr[t + 1][path[t + 1]];
}

//+------------------------------------------------------------------+
//| Detect if bar is a swing low                                     |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low[], int bar, int lookback)
{
   if(bar + lookback >= ArraySize(low)) return false;

   double centerLow = low[bar];

   // Check bars to the left (more recent)
   for(int i = 1; i <= lookback; i++)
   {
      if(bar - i < 0) return false;
      if(low[bar - i] <= centerLow) return false;
   }

   // Check bars to the right (older)
   for(int i = 1; i <= lookback; i++)
   {
      if(low[bar + i] <= centerLow) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Detect if bar is a swing high                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &high[], int bar, int lookback)
{
   if(bar + lookback >= ArraySize(high)) return false;

   double centerHigh = high[bar];

   // Check bars to the left (more recent)
   for(int i = 1; i <= lookback; i++)
   {
      if(bar - i < 0) return false;
      if(high[bar - i] >= centerHigh) return false;
   }

   // Check bars to the right (older)
   for(int i = 1; i <= lookback; i++)
   {
      if(high[bar + i] >= centerHigh) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpStates < 2 || InpStates > MAX_STATES)
   {
      Print("Invalid number of states. Recommend 2 for swing detection.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpTrainLen < 50 || InpTrainLen > MAX_T)
   {
      Print("Invalid training length. Must be 50..", MAX_T);
      return(INIT_PARAMETERS_INCORRECT);
   }

   SetIndexBuffer(0, SwingLowBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SwingHighBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);  // Up arrow
   PlotIndexSetInteger(1, PLOT_ARROW, 234);  // Down arrow

   ArraySetAsSeries(SwingLowBuffer, true);
   ArraySetAsSeries(SwingHighBuffer, true);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("HMM Swing Points (%d states, T=%d)", InpStates, InpTrainLen));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   // Set arrays as series
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if(rates_total < 50 + InpLookback * 2)
      return(0);

   int NStates = InpStates;
   if(NStates < 2) NStates = 2;
   if(NStates > MAX_STATES) NStates = MAX_STATES;

   int maxT = MathMin(InpTrainLen, rates_total - 1);
   if(maxT > MAX_T) maxT = MAX_T;
   if(maxT < 2) return(0);

   int T = maxT;

   //-------------------- BUILD OBSERVATIONS ------------------------//
   for(int t = 0; t < T; t++)
   {
      int i = t;
      double c0 = close[i];
      double c1 = close[i + 1];
      if(c0 > 0.0 && c1 > 0.0)
         obs[t] = MathLog(c0 / c1);
      else
         obs[t] = 0.0;
   }

   //---------------------- TRAIN HMM -------------------------------//
   InitializeHMM(NStates, T);
   BaumWelchTrain(NStates, T, InpMaxIter);

   //---------------------- VITERBI PATH ----------------------------//
   ViterbiDecode(NStates, T);

   //-------------- IDENTIFY WHICH STATE IS "CALM" VS "VOLATILE" ----//
   // State with higher variance is typically the volatile/trending state
   int volatileState = 0;
   int calmState = 0;

   if(NStates == 2)
   {
      volatileState = (sigma2[0] > sigma2[1]) ? 0 : 1;
      calmState = (volatileState == 0) ? 1 : 0;
   }

   //---------------------- DETECT SWING POINTS ---------------------//
   // Clear buffers
   for(int i = 0; i < rates_total; i++)
   {
      SwingLowBuffer[i] = EMPTY_VALUE;
      SwingHighBuffer[i] = EMPTY_VALUE;
   }

   // Scan for swing points
   for(int t = InpLookback; t < T - InpLookback; t++)
   {
      int bar = t;
      int currentState = path[t];

      bool stateChanged = false;
      if(t > 0)
         stateChanged = (path[t] != path[t - 1]);

      // Swing Low Detection:
      // - Transition TO calm state (end of volatile period)
      // - Price forms a swing low pattern
      if(InpShowOnTransition)
      {
         if(stateChanged && currentState == calmState)
         {
            if(IsSwingLow(low, bar, InpLookback))
            {
               SwingLowBuffer[bar] = low[bar];
            }
         }
      }
      else
      {
         // Just look for swing lows in calm state
         if(currentState == calmState && IsSwingLow(low, bar, InpLookback))
         {
            SwingLowBuffer[bar] = low[bar];
         }
      }

      // Swing High Detection:
      // - Transition TO volatile state OR end of calm period
      // - Price forms a swing high pattern
      if(InpShowOnTransition)
      {
         if(stateChanged && currentState == volatileState)
         {
            if(IsSwingHigh(high, bar, InpLookback))
            {
               SwingHighBuffer[bar] = high[bar];
            }
         }
      }
      else
      {
         // Just look for swing highs in volatile state
         if(currentState == volatileState && IsSwingHigh(high, bar, InpLookback))
         {
            SwingHighBuffer[bar] = high[bar];
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
