// ============================================================
// The J-Frame - Unified GAS Hub
// ============================================================
// このコードをGoogle Apps Scriptのエディタに貼り付けてください。
// 
// 事前準備:
// 1. Google Driveに「J-Frame_Screenshots」フォルダを作成
// 2. そのフォルダIDを下の SCREENSHOT_FOLDER_ID に設定
// 3. スプレッドシートに「TradeLog」シートを作成
//    ヘッダー行: ID | EntryTime | ExitTime | Currency | Model | Lots | SL_Pips | Outcome | Pips | RR | Profit | Note | ScreenshotURL | Source
// ============================================================

var SCREENSHOT_FOLDER_ID = "1GjRXSCUtsuELbuI-7_Y20gRbVEQLzPBa";

function doPost(e) {
  var p = e.parameter;
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName("TradeLog");
  if (!sheet) {
    sheet = ss.insertSheet("TradeLog");
    sheet.appendRow(["ID","エントリー日時","決済日時","通貨ペア","LRSモデル","判定ロット","SL幅(pips)","結果","獲得/損失pips","実現RR","実現損益","メモ","ScreenshotURL","Source"]);
  }

  var source = p.source || "gatekeeper";

  // ── Logger (MT5自動) からのリクエスト ──
  if (source === "logger") {
    return handleLogger(sheet, p);
  }

  // ── Gatekeeper (手動) からのリクエスト ──
  return handleGatekeeper(sheet, p);
}

// ── Logger処理: 決済検知 + スクショ保存 + 既存行マージ ──
function handleLogger(sheet, p) {
  var screenshotUrl = "";

  // スクショをGoogle Driveに保存
  if (p.screenshot && p.screenshot.length > 100) {
    try {
      var folder = DriveApp.getFolderById(SCREENSHOT_FOLDER_ID);
      var decoded = Utilities.base64Decode(p.screenshot);
      var blob = Utilities.newBlob(decoded, "image/gif", "shot_" + p.id + ".gif");
      var file = folder.createFile(blob);
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      screenshotUrl = file.getUrl();
    } catch (err) {
      Logger.log("Screenshot error: " + err);
    }
  }

  // 既存の「Pending」行(Gatekeeperで作成済み)を探してマージ
  var merged = false;
  var data = sheet.getDataRange().getValues();
  for (var i = 1; i < data.length; i++) {
    var rowCurrency = String(data[i][3]).replace(/\s/g, "");
    var rowExitTime = String(data[i][2]).trim();
    var rowOutcome  = String(data[i][7]).trim();

    // 同じ通貨で、まだExitTimeが空の行 = Gatekeeperで作ったPending行
    if (rowCurrency === String(p.currency).replace(/\s/g, "") && rowExitTime === "") {
      var rowNum = i + 1; // シートは1-indexed
      sheet.getRange(rowNum, 3).setValue(p.exitTime);       // ExitTime
      sheet.getRange(rowNum, 8).setValue(p.outcome);         // Outcome
      sheet.getRange(rowNum, 11).setValue(p.profit);         // Profit
      sheet.getRange(rowNum, 13).setValue(screenshotUrl);    // ScreenshotURL
      sheet.getRange(rowNum, 14).setValue("merged");         // Source
      merged = true;
      break;
    }
  }

  // マージ対象がない場合は新規行として追加
  if (!merged) {
    sheet.appendRow([
      p.id,           // ID
      "",             // EntryTime (なし)
      p.exitTime,     // ExitTime
      p.currency,     // Currency
      "",             // Model (なし)
      p.lots,         // Lots
      "",             // SL_Pips (なし)
      p.outcome,      // Outcome
      "",             // Pips (なし)
      "",             // RR (なし)
      p.profit,       // Profit
      "",             // Note
      screenshotUrl,  // ScreenshotURL
      "logger"        // Source
    ]);
  }

  return ContentService.createTextOutput(JSON.stringify({
    status: "ok",
    screenshotUrl: screenshotUrl,
    merged: merged
  })).setMimeType(ContentService.MimeType.JSON);
}

// ── Gatekeeper処理: エントリー記録 or 結果記録 ──
function handleGatekeeper(sheet, p) {
  // 結果記録 (exitTimeがある場合) → 既存行を更新
  if (p.exitTime) {
    var data = sheet.getDataRange().getValues();
    for (var i = 1; i < data.length; i++) {
      if (String(data[i][0]) === String(p.id)) {
        var rowNum = i + 1;
        sheet.getRange(rowNum, 3).setValue(p.exitTime);
        sheet.getRange(rowNum, 8).setValue(p.outcome || "");
        sheet.getRange(rowNum, 9).setValue(p.pips || "");
        sheet.getRange(rowNum, 10).setValue(p.rr || "");
        sheet.getRange(rowNum, 12).setValue(p.note || "");
        return ContentService.createTextOutput("Updated");
      }
    }
  }

  // エントリー記録 (新規行作成 = Pending状態)
  sheet.appendRow([
    p.id,              // ID
    p.entryTime,       // EntryTime
    "",                // ExitTime (Pending)
    p.currency,        // Currency
    p.modelStr || "",  // Model
    p.lots,            // Lots
    p.slPips || "",    // SL_Pips
    "",                // Outcome (Pending)
    "",                // Pips (Pending)
    "",                // RR (Pending)
    "",                // Profit (Pending)
    "",                // Note
    "",                // ScreenshotURL (Pending)
    "gatekeeper"       // Source
  ]);

  return ContentService.createTextOutput("Entry Recorded");
}

// ── GET: Gatekeeperから最新データを取得 ──
function doGet(e) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName("TradeLog");
  if (!sheet) return ContentService.createTextOutput("[]");

  var action = (e && e.parameter && e.parameter.action) ? e.parameter.action : "recent";

  if (action === "pending") {
    // Pending(未決済)の行だけ返す
    return getPendingTrades(sheet);
  }

  // 最新10件を返す
  return getRecentTrades(sheet);
}

function getPendingTrades(sheet) {
  var data = sheet.getDataRange().getValues();
  var headers = data[0];
  var result = [];

  for (var i = 1; i < data.length; i++) {
    var exitTime = String(data[i][2]).trim();
    if (exitTime === "") {
      var row = {};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = data[i][j];
      }
      result.push(row);
    }
  }

  return ContentService.createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

function getRecentTrades(sheet) {
  var data = sheet.getDataRange().getValues();
  var headers = data[0];
  var result = [];

  var start = Math.max(1, data.length - 10);
  for (var i = start; i < data.length; i++) {
    var row = {};
    for (var j = 0; j < headers.length; j++) {
      row[headers[j]] = data[i][j];
    }
    result.push(row);
  }

  return ContentService.createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}
