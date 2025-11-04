# CandleShift - Dynamic Candle Time Shift Indicator for MT5

A MetaTrader 5 (MT5) custom indicator that creates dynamic candlestick charts with adjustable time shifts. This indicator builds custom timeframe candles from 1-minute data and allows you to shift the candle start times left or right by 1-minute increments.

## Features

- **Dynamic Online Charts**: Real-time updates with live price movements
- **Custom Timeframe**: Configurable candle period (default: 15 minutes)
- **Time Shift Control**: Shift candle start times left or right by 1 minute
- **Interactive Buttons**: Easy-to-use LEFT and RIGHT buttons on the chart
- **Visual Feedback**: Info label showing current shift and candle times
- **Built from M1 Data**: Uses 1-minute chart data as the foundation

## How It Works

### Standard Candles (No Shift)
For a 15-minute timeframe:
- **Standard times**: 15:00, 15:15, 15:30, 15:45, etc.

### Shifted Left by 1 Minute
When you press the LEFT button once:
- **Shifted times**: 14:59, 15:14, 15:29, 15:44, etc.

### Shifted Right by 1 Minute
When you press the RIGHT button once:
- **Shifted times**: 15:01, 15:16, 15:31, 15:46, etc.

You can continue pressing the buttons to increase the shift in either direction.

## Installation

1. **Locate your MT5 Data Folder**:
   - Open MetaTrader 5
   - Click `File` → `Open Data Folder`
   - This will open your MT5 data directory

2. **Copy the Indicator File**:
   - Navigate to `MQL5/Indicators/` folder
   - Copy `DynamicCandleShift.mq5` from this repository to that folder

3. **Compile the Indicator** (if needed):
   - Open MetaEditor (press F4 in MT5 or click the IDE icon)
   - Open the `DynamicCandleShift.mq5` file
   - Press F7 to compile
   - You should see "0 error(s), 0 warning(s)" in the compilation results

4. **Refresh MT5**:
   - Return to MT5
   - In the Navigator panel, right-click on `Indicators` and select `Refresh`

## Usage

### Adding to a Chart

1. Open any chart in MT5 (the indicator will use M1 data regardless of current timeframe)
2. In the Navigator panel, expand `Indicators` → `Custom`
3. Find `DynamicCandleShift` and drag it onto the chart
4. Configure the parameters (or use defaults) and click OK

### Input Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **CandlePeriod** | 15 | Candle period in minutes (e.g., 5, 15, 30, 60) |
| **InitialShift** | 0 | Initial time shift in minutes |
| **ButtonColorLeft** | Green | Color of the LEFT button |
| **ButtonColorRight** | Green | Color of the RIGHT button |
| **ButtonWidth** | 80 | Width of buttons in pixels |
| **ButtonHeight** | 30 | Height of buttons in pixels |
| **ButtonX** | 20 | Horizontal position from left edge |
| **ButtonY** | 50 | Vertical position from top edge |

### Using the Shift Buttons

- **LEFT Button (◄)**: Shifts candle start times 1 minute earlier
  - Example: 15:00 → 14:59 → 14:58 → ...

- **RIGHT Button (►)**: Shifts candle start times 1 minute later
  - Example: 15:00 → 15:01 → 15:02 → ...

### Info Label

The info label at the top of the chart displays:
- Current shift value (in minutes)
- Candle period
- Example of next three candle start times

Example: `Shift: -2 min | Period: 15 min | Times: 14:58, 15:13, 15:28...`

## Technical Details

### How Candles Are Calculated

1. The indicator copies 1-minute (M1) data for the current symbol
2. For each M1 bar, it calculates which custom candle period it belongs to based on the current shift
3. M1 bars are aggregated into custom candles:
   - **Open**: First M1 open in the period
   - **High**: Highest M1 high in the period
   - **Low**: Lowest M1 low in the period
   - **Close**: Last M1 close in the period
4. Candles update in real-time as new M1 data arrives

### Chart Requirements

- The indicator works on any chart timeframe (it uses M1 data internally)
- Requires sufficient M1 historical data for your symbol
- Works with all instruments supported by MT5 (Forex, Stocks, Commodities, etc.)

## Examples

### Example 1: 15-Minute Candles with -3 Minute Shift

**Configuration**:
- CandlePeriod: 15
- Shift: -3 (after clicking LEFT button 3 times)

**Result**:
- Candle times: 14:57, 15:12, 15:27, 15:42, 15:57, etc.

### Example 2: 5-Minute Candles with +2 Minute Shift

**Configuration**:
- CandlePeriod: 5
- Shift: +2 (after clicking RIGHT button 2 times)

**Result**:
- Candle times: 15:02, 15:07, 15:12, 15:17, 15:22, etc.

## Troubleshooting

### Indicator Not Showing Candles

- **Check M1 Data**: Ensure you have 1-minute historical data for your symbol
  - Right-click chart → `Time frames` → `M1`
  - Wait for data to load
  - Return to your preferred timeframe

- **Check Logs**: Open the Experts tab in the Terminal window (Ctrl+T) for error messages

### Buttons Not Visible

- **Adjust Position**: Try different ButtonX and ButtonY values
- **Chart Layers**: Ensure the chart is in foreground (not covered by other windows)

### Candles Look Strange

- **Verify Period**: Make sure CandlePeriod is reasonable (5, 10, 15, 30, 60, etc.)
- **Reset Shift**: Try setting shift back to 0 to see standard candles

## Use Cases

### Trading Strategy Development
- Test how different candle alignments affect support/resistance levels
- Identify patterns that appear at non-standard time intervals
- Optimize entry/exit timing based on custom candle periods

### Market Analysis
- Avoid common psychological levels (e.g., hourly candles at :00)
- Find better candle boundaries for your trading style
- Reduce noise by aligning candles with actual market behavior

### Backtesting
- Validate strategies across different time alignments
- Check if your strategy is too dependent on standard candle times
- Improve robustness by testing multiple shift values

## License

Copyright 2025, CandleShift

## Support

For issues, questions, or contributions, please open an issue in the GitHub repository.

## Version History

- **v1.00** (2025-11-04): Initial release
  - Dynamic candle calculation from M1 data
  - Left/Right shift buttons
  - Real-time updates
  - Configurable parameters
