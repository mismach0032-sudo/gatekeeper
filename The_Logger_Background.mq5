//+------------------------------------------------------------------+
//|                                     The_Logger_Background.mq5    |
//|                                      Copyright 2026, The J-Frame |
//+------------------------------------------------------------------+
#property copyright "The J-Frame"
#property link      ""
#property version   "1.00"
#property description "The J-Frame 'Auto-Logger' - Background Script Version"
// スクリプトとして実行（チャートに依存しない）
#property script_show_inputs

//--- 入力パラメーター
input string   GAS_URL = "https://script.google.com/macros/s/AKfycbwPcsEmC_R34sv1tbz5UlsEscIEeXOgA3OJlxvGGnadtbGRPZNL9RRl6PBtXQ8vmqdo/exec";
input int      CheckIntervalSec = 30;

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   Print("The Logger (Background Script) started. Press 'Stop' in Terminal to kill.");
   
   datetime lastCheckedTime = TimeCurrent();
   
   // 無限ループで疑似的に常駐させる（スクリプト特有の手法）
   // IsStopped() はユーザーが明示的に「停止」を押すかMT5終了時までfalseを返す
   while(!IsStopped())
     {
      datetime currentTime = TimeCurrent();
      
      // 前回チェック時刻から現在までの履歴を取得
      if(HistorySelect(lastCheckedTime, currentTime))
        {
         int dealsTotal = HistoryDealsTotal();
         
         for(int i = 0; i < dealsTotal; i++)
           {
            ulong dealTicket = HistoryDealGetTicket(i);
            
            if(dealTicket > 0)
              {
               long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
               
               if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
                 {
                  datetime dealTime   = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                  string   symbol     = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                  double   volume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                  double   profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                  double   commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                  double   swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                  
                  double totalProfit = profit + commission + swap;
                  string outcome = "BE";
                  if(totalProfit > 0) outcome = "WIN";
                  else if(totalProfit < 0) outcome = "LOSS";
                  
                  string timeStr = TimeToString(dealTime, TIME_DATE|TIME_MINUTES);
                  timeStr = StringReplace(timeStr, ".", "-");
                  
                  PrintFormat("New Exit Detected (Script): Ticket=%d, Time=%s, Symbol=%s, Vol=%.2f, Profit=%.2f (%s)", 
                              dealTicket, timeStr, symbol, volume, totalProfit, outcome);
                              
                  SendToGAS(dealTicket, timeStr, symbol, volume, totalProfit, outcome);
                 }
              }
           }
        }
        
      lastCheckedTime = currentTime;
      
      // 指定秒数スリープして、CPUの負荷を下げる（1000ミリ秒 = 1秒）
      Sleep(CheckIntervalSec * 1000);
     }
     
   Print("The Logger (Background Script) stopped manually.");
  }

//+------------------------------------------------------------------+
//| URLエンコード関数                                                  |
//+------------------------------------------------------------------+
string UrlEncode(string text)
  {
   string result = "";
   for(int i = 0; i < StringLen(text); i++)
     {
      ushort c = StringGetCharacter(text, i);
      if((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
         c == '-' || c == '_' || c == '.' || c == '~')
        {
         result += ShortToString(c);
        }
      else if(c == ' ') { result += "+"; }
      else { result += StringFormat("%%%02X", c); }
     }
   return result;
  }

//+------------------------------------------------------------------+
//| M15チャートのスクショを撮影しBase64で取得                              |
//+------------------------------------------------------------------+
string CaptureM15Base64(string symbol)
  {
   long chartId = 0;
   long firstChart = ChartFirst();
   chartId = firstChart;
   
   // M15チャートを探す
   while(chartId >= 0)
     {
      if(ChartSymbol(chartId) == symbol && ChartPeriod(chartId) == PERIOD_M15)
         break;
      chartId = ChartNext(chartId);
     }
   
   // 見つからない場合は最初のチャートを使う（それもなければ0）
   if(chartId < 0) chartId = firstChart;
   if(chartId < 0) return "";

   string fileName = "shot_" + symbol + ".gif"; // 軽量化のためgifまたは小さめの幅を指定
   if(!ChartScreenShot(chartId, fileName, 800, 450)) // 16:9 
     {
      Print("Screenshot failed. Error: ", GetLastError());
      return "";
     }

   // ファイルを読み込んでBase64に変換
   ResetLastError();
   int handle = FileOpen(fileName, FILE_READ|FILE_BIN|FILE_COMMON);
   if(handle == INVALID_HANDLE) 
     {
      // 共通フォルダにない場合は通常フォルダ
      handle = FileOpen(fileName, FILE_READ|FILE_BIN);
     }
     
   if(handle == INVALID_HANDLE) return "";
   
   uchar data[];
   FileReadArray(handle, data);
   FileClose(handle);

   return Base64Encode(data);
  }

//+------------------------------------------------------------------+
//| Base64エンコード (簡易実装)                                          |
//+------------------------------------------------------------------+
string Base64Encode(uchar &source[])
  {
   string base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
   string result = "";
   int len = ArraySize(source);
   
   for(int i = 0; i < len; i += 3)
     {
      uint a = source[i];
      uint b = (i + 1 < len) ? source[i + 1] : 0;
      uint c = (i + 2 < len) ? source[i + 2] : 0;
      
      result += StringSubstr(base64, (a >> 2) & 0x3F, 1);
      result += StringSubstr(base64, ((a << 4) | (b >> 4)) & 0x3F, 1);
      
      if(i + 1 < len)
         result += StringSubstr(base64, ((b << 2) | (c >> 6)) & 0x3F, 1);
      else
         result += "=";
         
      if(i + 2 < len)
         result += StringSubstr(base64, c & 0x3F, 1);
      else
         result += "=";
     }
   return result;
  }

//+------------------------------------------------------------------+
//| GASへWebRequestを使ってデータ送信                                  |
//+------------------------------------------------------------------+
bool SendToGAS(ulong ticket, string timeStr, string symbol, double volume, double profit, string outcome)
  {
   if(GAS_URL == "") return false;

   // スクショ撮影
   string base64Img = CaptureM15Base64(symbol);

   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string params = "source=logger" +
                   "&id=MT5_" + IntegerToString(ticket) + 
                   "&exitTime=" + UrlEncode(timeStr) +
                   "&currency=" + UrlEncode(symbol) +
                   "&lots=" + DoubleToString(volume, 2) +
                   "&profit=" + DoubleToString(profit, 2) +
                   "&outcome=" + UrlEncode(outcome) +
                   "&screenshot=" + UrlEncode(base64Img); // スクショ追加
                   
   char postData[];
   StringToCharArray(params, postData, 0, StringLen(params));
   
   char resultData[];
   string resultHeaders;
   int res = WebRequest("POST", GAS_URL, headers, 10000, postData, resultData, resultHeaders);
   
   if(res == 200)
     {
      Print("Sync Success (Script) with Screenshot! Ticket: ", ticket);
      return true;
     }
   else
     {
      Print("Sync Failed. HTTP code: ", res, " Error code: ", GetLastError());
      return false;
     }
  }
