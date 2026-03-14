//+------------------------------------------------------------------+
//|                                                  The_Watcher.mq5 |
//|                                      Copyright 2026, The J-Frame |
//+------------------------------------------------------------------+
#property copyright "The J-Frame"
#property link      ""
#property version   "1.00"
#property description "The J-Frame 'Watcher' - Auto-monitors Fibo 50-61.8% zone and pushes notifications."

input bool   EnableAlerts = true;       // アラート（プッシュ通知）を有効にするか

string lastFiboName = "";
bool alertSent = false;
bool isZoneActive = false;
double zoneHigh = 0.0;
double zoneLow = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("The Watcher (Fibo Auto-Alert) started.");
   EventSetTimer(1); // 1秒ごとにチェック (Tickではなく時間ベースで安定監視)
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment(""); // チャートのコメントを消去
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   string currentFibo = GetLatestFiboName();
   
   // フィボナッチがない場合
   if(currentFibo == "")
     {
      Comment("【The Watcher】\nフィボナッチ(R1)を検知できません。\nR1波にFiboを引いてください。");
      isZoneActive = false;
      return;
     }
     
   // 新しいフィボナッチが引かれた（または別名になった）場合リセット
   if(currentFibo != lastFiboName)
     {
      lastFiboName = currentFibo;
      alertSent = false;
      Print("The Watcher: New Fibo detected -> ", currentFibo);
     }
     
   // フィボの0%と100%価格を取得
   double p1 = ObjectGetDouble(0, currentFibo, OBJPROP_PRICE, 0); // 始点 (100%)
   double p2 = ObjectGetDouble(0, currentFibo, OBJPROP_PRICE, 1); // 終点 (0%)
   
   // エラー判定（価格が取れない等）
   if(p1 == 0 || p2 == 0) return;
   
   double highPrice = MathMax(p1, p2);
   double lowPrice  = MathMin(p1, p2);
   double diff = highPrice - lowPrice;
   
   // 50%と61.8%の価格帯を算出
   if(p1 < p2) // 上昇トレンド(下から上に引いた場合：押し目を待つ)
     {
      zoneHigh = p2 - (diff * 0.500);
      zoneLow  = p2 - (diff * 0.618);
     }
   else // 下降トレンド(上から下に引いた場合：戻り目を待つ)
     {
      zoneHigh = p2 + (diff * 0.618);
      zoneLow  = p2 + (diff * 0.500);
     }
     
   isZoneActive = true;
   
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // 画面左上にステータスを表示
   string statusStr = "【The Watcher 稼働中】\n";
   statusStr += "監視通貨: " + _Symbol + "\n";
   statusStr += "ターゲットFibo: " + currentFibo + "\n";
   statusStr += StringFormat("R2 待機ゾーン (50-61.8%%):  %.3f 〜 %.3f\n", MathMax(zoneHigh, zoneLow), MathMin(zoneHigh, zoneLow));
   statusStr += StringFormat("現在価格(Bid): %.3f\n", currentBid);
   
   if(alertSent)
     {
      statusStr += "\n✅ アラート送信済み。Gatekeeperを開き、S波ダウ転換を待て。";
     }
   else
     {
      statusStr += "\n⏳ ゾーン到達を監視中...";
     }
     
   Comment(statusStr);
   
   // アラート判定 (まだ送っていない場合のみ)
   if(EnableAlerts && !alertSent)
     {
      // ゾーン内に価格が入ったか判定
      if(currentBid <= MathMax(zoneHigh, zoneLow) && currentBid >= MathMin(zoneHigh, zoneLow))
        {
         string msg = "🚀 The J-Frame [Watcher]\n" + _Symbol + " : R2 Zone (50-61.8%) REACHED!\nOpen Gatekeeper to execute.";
         
         // ネイティブプッシュ通知
         SendNotification(msg);
         
         // 念のためPC上でもアラート音を鳴らす
         Alert(msg);
         
         Print("Push Notification Sent: ", msg);
         alertSent = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| 最新のフィボナッチ・リトレースメントの名前を取得する             |
//+------------------------------------------------------------------+
string GetLatestFiboName()
  {
   int total = ObjectsTotal(0, 0, OBJ_FIBO);
   if(total == 0) return "";
   
   long maxTime = 0;
   string newestName = "";
   
   for(int i=0; i<total; i++)
     {
      string name = ObjectName(0, i, 0, OBJ_FIBO);
      long createTime = ObjectGetInteger(0, name, OBJPROP_CREATETIME);
      if(createTime >= maxTime)
        {
         maxTime = createTime;
         newestName = name;
        }
     }
   return newestName;
  }
//+------------------------------------------------------------------+
