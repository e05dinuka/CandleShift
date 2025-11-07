//+------------------------------------------------------------------+
//|                                                   HMM_Regime.mq5 |
//|   Gaussian HMM (Baum–Welch + Viterbi) regime detector            |
//|   Educational / experimental example                             |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots   2
#property indicator_buffers 2

#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label1  "Regime 1"

#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label2  "Regime 2"

//---------------------------- SETTINGS ------------------------------//
#define MAX_T       1000          // max training length (bars)
#define MAX_STATES  3             // hard cap on HMM states
#define NEG_INF     -1e100        // log(0) sentinel

input int    InpStates     = 2;       // Number of HMM states (1..3)
input int    InpTrainLen   = 300;     // Max bars used for training (<= MAX_T)
input int    InpMaxIter    = 10;      // Baum–Welch iterations
input double InpMinSigma2  = 1e-6;    // Min variance to avoid degenerate Gaussians
input double InpMinProb    = 1e-8;    // Min probability (for logs)

//------------------------ INDICATOR BUFFERS -------------------------//
double Regime1Buffer[];
double Regime2Buffer[];

//--------------------- HMM GLOBAL ARRAYS ----------------------------//
// Observations (log returns)
double obs[MAX_T];

// HMM parameters
double piArr[MAX_STATES];                // initial state probs π_i
double A[MAX_STATES][MAX_STATES];        // transition matrix A_ij
double mu[MAX_STATES];                   // Gaussian means
double sigma2[MAX_STATES];               // Gaussian variances

// Baum–Welch (log-space) work arrays
double logAlpha[MAX_T][MAX_STATES];
double logBeta[MAX_T][MAX_STATES];
double gammaArr[MAX_T][MAX_STATES];

// Viterbi arrays
double logDelta[MAX_T][MAX_STATES];
int    psiArr[MAX_T][MAX_STATES];
int    path[MAX_T];

//+------------------------------------------------------------------+
//| Helper: log-sum-exp for two numbers (numerical stability)        |
//+------------------------------------------------------------------+
double LogSumExp(double a, double b)
{
   if(a <= NEG_INF) return b;
   if(b <= NEG_INF) return a;
   double m = (a > b ? a : b);
   return m + MathLog(MathExp(a - m) + MathExp(b - m));
}

//+------------------------------------------------------------------+
//| Gaussian log emission log P(o | state)                           |
//| Returns log-likelihood (without normalization constant)          |
//+------------------------------------------------------------------+
double LogEmissionProb(const int state, const double o)
{
   double v = sigma2[state];
   if(v < InpMinSigma2) v = InpMinSigma2;
   double diff = o - mu[state];
   // Return log-likelihood (normalization constant omitted - only relative values matter)
   double exponent = -0.5 * diff * diff / v;
   return exponent;
}

//+------------------------------------------------------------------+
//| Initialize HMM parameters from data                              |
//+------------------------------------------------------------------+
void InitializeHMM(const int NStates, const int T)
{
   // Basic mean/variance of observations
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

   // Initial π: uniform
   for(int i = 0; i < NStates; i++)
      piArr[i] = 1.0 / (double)NStates;

   // Initial A: uniform ergodic
   for(int i = 0; i < NStates; i++)
      for(int j = 0; j < NStates; j++)
         A[i][j] = 1.0 / (double)NStates;

   // Initial means: spread around global mean
   double step = (NStates > 1 ? 1.0 / (double)(NStates - 1) : 0.0);
   double sdev = MathSqrt(var);
   for(int i = 0; i < NStates; i++)
   {
      double offset = (step * i - 0.5) * sdev;   // roughly from -0.5σ to +0.5σ
      mu[i]      = mean + offset;
      sigma2[i]  = var;
   }
}

//+------------------------------------------------------------------+
//| Baum–Welch training in log-space                                 |
//+------------------------------------------------------------------+
void BaumWelchTrain(const int NStates, const int T, const int maxIter)
{
   for(int iter = 0; iter < maxIter; iter++)
   {
      //-------------------- FORWARD (log-alpha) --------------------//
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

      //-------------------- BACKWARD (log-beta) --------------------//
      for(int i = 0; i < NStates; i++)
         logBeta[T - 1][i] = 0.0;  // log(1)

      for(int t = T - 2; t >= 0; t--)
      {
         for(int i = 0; i < NStates; i++)
         {
            double ls = NEG_INF;
            for(int j = 0; j < NStates; j++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double cand = MathLog(a)
                             + LogEmissionProb(j, obs[t + 1])
                             + logBeta[t + 1][j];
               ls = LogSumExp(ls, cand);
            }
            logBeta[t][i] = ls;
         }
      }

      //----------------------- GAMMA & XI SUMS ----------------------//
      double denomA[MAX_STATES];
      double numerA[MAX_STATES][MAX_STATES];

      // zero accumulators
      for(int i = 0; i < NStates; i++)
      {
         denomA[i] = 0.0;
         for(int j = 0; j < NStates; j++)
            numerA[i][j] = 0.0;
      }

      // gamma for all t
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

      // xi sums for A-ij
      for(int t = 0; t < T - 1; t++)
      {
         // log denominator for xi at time t
         double logDenomXi = NEG_INF;
         for(int i = 0; i < NStates; i++)
         {
            for(int j = 0; j < NStates; j++)
            {
               double a = A[i][j];
               if(a < InpMinProb) a = InpMinProb;
               double logTerm = logAlpha[t][i]
                                + MathLog(a)
                                + LogEmissionProb(j, obs[t + 1])
                                + logBeta[t + 1][j];
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
               double logNumer = logAlpha[t][i]
                                 + MathLog(a)
                                 + LogEmissionProb(j, obs[t + 1])
                                 + logBeta[t + 1][j];
               double xi_t_ij = MathExp(logNumer - logDenomXi);
               if(xi_t_ij < InpMinProb) xi_t_ij = InpMinProb;
               numerA[i][j] += xi_t_ij;
               gamma_t_i    += xi_t_ij;
            }
            denomA[i] += gamma_t_i;   // sum_t gamma_t(i) for t=0..T-2
         }
      }

      //------------------------ UPDATE π ---------------------------//
      for(int i = 0; i < NStates; i++)
         piArr[i] = gammaArr[0][i];

      //------------------------ UPDATE A ---------------------------//
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
         // normalize row
         if(rowsum > 0.0)
         {
            for(int j = 0; j < NStates; j++)
               A[i][j] /= rowsum;
         }
      }

      //--------------------- UPDATE μ & σ² --------------------------//
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
//| Viterbi decoding (most likely state path)                        |
//+------------------------------------------------------------------+
void ViterbiDecode(const int NStates, const int T)
{
   // Init
   for(int i = 0; i < NStates; i++)
   {
      double p = piArr[i];
      if(p < InpMinProb) p = InpMinProb;
      logDelta[0][i] = MathLog(p) + LogEmissionProb(i, obs[0]);
      psiArr[0][i]   = 0;
   }

   // Recursion
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

   // Termination
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

   // Backtrack
   path[T - 1] = bestState;
   for(int t = T - 2; t >= 0; t--)
      path[t] = psiArr[t + 1][path[t + 1]];
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpStates < 1 || InpStates > MAX_STATES)
   {
      Print("Invalid number of states. Must be 1..", MAX_STATES);
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(InpTrainLen < 50 || InpTrainLen > MAX_T)
   {
      Print("Invalid training length. Must be 50..", MAX_T);
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Set buffers
   SetIndexBuffer(0, Regime1Buffer, INDICATOR_DATA);
   SetIndexBuffer(1, Regime2Buffer, INDICATOR_DATA);

   ArraySetAsSeries(Regime1Buffer, true);
   ArraySetAsSeries(Regime2Buffer, true);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("HMM Regime (%d states, T=%d)", InpStates, InpTrainLen));

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
   //--------------- CRITICAL: SET ARRAYS AS SERIES -----------------//
   // MQL5 does NOT automatically set price arrays as series in OnCalculate
   // Without this, close[0] would be the OLDEST bar (wrong!)
   // With this, close[0] is the NEWEST bar (correct!)
   ArraySetAsSeries(close, true);

   // Need enough bars to be meaningful
   if(rates_total < 50)
   {
      return(0);
   }

   int NStates = InpStates;
   if(NStates < 1) NStates = 1;
   if(NStates > MAX_STATES) NStates = MAX_STATES;

   // T is the number of returns we can compute
   // We need T+1 prices to compute T returns
   int maxT = MathMin(InpTrainLen, rates_total - 1);
   if(maxT > MAX_T) maxT = MAX_T;
   if(maxT < 2) return(0);  // Need at least 2 points

   int T = maxT;

   //-------------------- BUILD OBSERVATIONS ------------------------//
   // Compute log-returns: log(close[i] / close[i+1])
   // With ArraySetAsSeries:
   //   close[0] = most recent bar
   //   close[1] = previous bar, etc.
   // So log(close[i]/close[i+1]) = return from bar i+1 (older) to bar i (newer)
   //
   // obs[0] = return from bar 1 to bar 0 (most recent return)
   // obs[t] = return from bar t+1 to bar t
   //
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

   //---------------------- TRAIN HMM (EM) --------------------------//
   InitializeHMM(NStates, T);
   BaumWelchTrain(NStates, T, InpMaxIter);

   //---------------------- VITERBI PATH ----------------------------//
   ViterbiDecode(NStates, T);

   //---------------------- FILL BUFFERS ----------------------------//
   // Clear all buffers first
   for(int i = 0; i < rates_total; i++)
   {
      Regime1Buffer[i] = EMPTY_VALUE;
      Regime2Buffer[i] = EMPTY_VALUE;
   }

   // Map decoded states to buffers
   // path[t] = HMM state at time t
   // Since time t corresponds to bar t (with series indexing):
   //   path[0] = state at bar 0 (most recent)
   //   path[t] = state at bar t
   //
   for(int t = 0; t < T; t++)
   {
      int bar   = t;
      int state = path[t];

      // For 2 states: state 0 -> Regime1 (Lime), state 1 -> Regime2 (Red)
      // For 3 states: fold state 2 into one of the regimes
      if(state == 0)
      {
         Regime1Buffer[bar] = close[bar];
         Regime2Buffer[bar] = EMPTY_VALUE;
      }
      else if(state == 1)
      {
         Regime1Buffer[bar] = EMPTY_VALUE;
         Regime2Buffer[bar] = close[bar];
      }
      else
      {
         // State 2 or higher: fold into one of the two display regimes
         if((state % 2) == 0)
         {
            Regime1Buffer[bar] = close[bar];
            Regime2Buffer[bar] = EMPTY_VALUE;
         }
         else
         {
            Regime1Buffer[bar] = EMPTY_VALUE;
            Regime2Buffer[bar] = close[bar];
         }
      }
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
