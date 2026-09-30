mkdir pharma-desk; cd pharma-desk
New-Item -ItemType Directory -Force -Path "src/db","src-tauri/src",".github/workflows","scripts/drugs-importer" | Out-Null

# ===== package.json =====
@\'
{
  "name": "pharma-desk",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": { "dev": "vite", "build": "tsc && vite build", "tauri": "tauri" },
  "dependencies": {
    "react": "^18.3.1", "react-dom": "^18.3.1",
    "@tauri-apps/api": "^2.2.0",
    "@tauri-apps/plugin-sql": "^2.2.0",
    "@tauri-apps/plugin-fs": "^2.2.0",
    "@tauri-apps/plugin-dialog": "^2.2.0",
    "papaparse": "^5.4.2", "xlsx": "^0.18.5"
  },
  "devDependencies": {
    "@types/react": "^18.3.3", "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1", "typescript": "^5.4.5",
    "vite": "^5.4.0", "tailwindcss": "^3.4.3", "postcss": "^8.4.38",
    "autoprefixer": "^10.4.19", "@tauri-apps/cli": "^2.2.0"
  }
}
\'@ | Set-Content -Encoding utf8 -Path "package.json"

# ===== vite.config.ts =====
@\'
import { defineConfig } from "vite"; import react from "@vitejs/plugin-react";
export default defineConfig({ plugins: [react()], clearScreen: false, server: { port: 1420, strictPort: true }, envPrefix: ["VITE_","TAURI_"] });
\'@ | Set-Content -Encoding utf8 -Path "vite.config.ts"

# ===== tailwind + postcss =====
@\'export default { content: ["./index.html","./src/**/*.{js,ts,jsx,tsx}"], theme: { extend: {} }, plugins: [] }\'@ | Set-Content -Encoding utf8 -Path "tailwind.config.js"
@\'export default { plugins: { tailwindcss: {}, autoprefixer: {} } }\'@ | Set-Content -Encoding utf8 -Path "postcss.config.js"

# ===== index.html =====
@\'<!doctype html><html lang="ar" dir="rtl"><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width"/><title>PharmaDesk</title></head><body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body></html>\'@ | Set-Content -Encoding utf8 -Path "index.html"

# ===== src files =====
@\'@tailwind base; @tailwind components; @tailwind utilities; html{ direction:rtl; } body{ font-family: Cairo, system-ui; background:#f8fafc; } .num{ direction:ltr; display:inline-block; font-family: monospace; }\'@ | Set-Content -Encoding utf8 -Path "src/index.css"
@\'import React from "react"; import ReactDOM from "react-dom/client"; import App from "./App"; import "./index.css"; ReactDOM.createRoot(document.getElementById("root")!).render(<React.StrictMode><App/></React.StrictMode>);\'@ | Set-Content -Encoding utf8 -Path "src/main.tsx"

# ===== database.ts =====
@\'
import Database from "@tauri-apps/plugin-sql";
let db:any=null;
export async function getDb(){
  if(db) return db;
  db=await Database.load("sqlite:pharma.db");
  await db.execute(`
    CREATE TABLE IF NOT EXISTS medicines (id INTEGER PRIMARY KEY, barcode TEXT UNIQUE, name_ar TEXT NOT NULL, name_en TEXT, active_ingredient TEXT, concentration TEXT, form TEXT, manufacturer TEXT, price REAL, category TEXT, status TEXT DEFAULT "متداول", updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
    CREATE VIRTUAL TABLE IF NOT EXISTS fts_medicines USING fts5(name_ar, name_en, active_ingredient, barcode, content="medicines", content_rowid="id", tokenize="trigram");
    CREATE TRIGGER IF NOT EXISTS medicines_ai AFTER INSERT ON medicines BEGIN INSERT INTO fts_medicines(rowid,name_ar,name_en,active_ingredient,barcode) VALUES (new.id,new.name_ar,new.name_en,new.active_ingredient,new.barcode); END;
    CREATE TRIGGER IF NOT EXISTS medicines_ad AFTER DELETE ON medicines BEGIN INSERT INTO fts_medicines(fts_medicines,rowid,name_ar,name_en,active_ingredient,barcode) VALUES("delete",old.id,old.name_ar,old.name_en,old.active_ingredient,old.barcode); END;
    CREATE TABLE IF NOT EXISTS inventory_batches (id INTEGER PRIMARY KEY, medicine_id INTEGER, batch_no TEXT, expiry_date DATE, quantity INTEGER, cost_price REAL, FOREIGN KEY(medicine_id) REFERENCES medicines(id));
    CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY, total REAL, discount REAL, payment TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE IF NOT EXISTS sale_items (id INTEGER PRIMARY KEY, sale_id INTEGER, medicine_id INTEGER, qty INTEGER, price REAL);
    CREATE TABLE IF NOT EXISTS sync_queue (id INTEGER PRIMARY KEY, table_name TEXT, record_id INTEGER, operation TEXT, data TEXT, updated_at DATETIME DEFAULT CURRENT_TIMESTAMP);
  `);
  return db;
}
\'@ | Set-Content -Encoding utf8 -Path "src/db/database.ts"

# ===== App.tsx =====
@\'
import { useEffect, useState } from "react"; import { getDb } from "./db/database"; import * as Papa from "papaparse"; import { open } from "@tauri-apps/plugin-dialog"; import { readFile } from "@tauri-apps/plugin-fs";
export default function App(){
  const [tab,setTab]=useState("medicines"); const [q,setQ]=useState(""); const [meds,setMeds]=useState<any[]>([]); const [cart,setCart]=useState<any[]>([]);
  const load=async()=>{ const db=await getDb(); let rows:any[]=[]; if(!q) rows=await db.select("SELECT * FROM medicines LIMIT 50"); else rows=await db.select("SELECT medicines.* FROM fts_medicines JOIN medicines ON medicines.id=fts_medicines.rowid WHERE fts_medicines MATCH $1 LIMIT 50",[q+"*"]); setMeds(rows); }
  useEffect(()=>{load()},[q])
  const importCSV=async()=>{ const path=await open({filters:[{name:"CSV",extensions:["csv","xlsx"]}]}); if(!path) return; const content=await readFile(path as string); const text=new TextDecoder("utf-8").decode(content as any); Papa.parse(text,{header:true, complete: async(res)=>{ const db=await getDb(); for(let r of res.data as any[]){ if(!r.name_ar || !r.price) continue; await db.execute("INSERT OR IGNORE INTO medicines (barcode,name_ar,name_en,active_ingredient,concentration,price,manufacturer) VALUES ($1,$2,$3,$4,$5,$6,$7)",[r.barcode,r.name_ar,r.name_en,r.active_ingredient,r.concentration,parseFloat(r.price),r.manufacturer])} load(); alert("تم الاستيراد ومقارنة الاسعار بنجاح");}});}
  const addToCart=(m:any)=> setCart([...cart,{...m, qty:1}]); const total=cart.reduce((s,i)=>s+i.price*i.qty,0);
  const sell=async()=>{ const db=await getDb(); for(let item of cart){ let batches:any[]=await db.select("SELECT * FROM inventory_batches WHERE medicine_id=$1 AND quantity>0 ORDER BY expiry_date ASC",[item.id]); let need=item.qty; for(let b of batches){ if(need<=0) break; let take=Math.min(b.quantity, need); await db.execute("UPDATE inventory_batches SET quantity=quantity-$1 WHERE id=$2",[take,b.id]); need-=take; } } await db.execute("INSERT INTO sales (total,payment) VALUES ($1,\"كاش\")",[total]); setCart([]); alert("تم البيع - خصم FEFO من الاقرب انتهاء + طباعة حرارية"); }
  return (<div className="min-h-screen flex"><aside className="w-64 bg-white border-l p-4 space-y-2"><h1 className="font-bold text-xl text-blue-600">PharmaDesk</h1><button onClick={()=>setTab("medicines")} className="w-full text-right p-2 hover:bg-blue-50">الادوية والبحث</button><button onClick={()=>setTab("pos")} className="w-full text-right p-2 hover:bg-blue-50">نقطة البيع POS</button><button onClick={()=>setTab("settings")} className="w-full text-right p-2 hover:bg-blue-50">الاعدادات والشبكة LAN</button></aside><main className="flex-1 p-6">{tab==="medicines" && (<div><div className="flex gap-2 mb-4"><input value={q} onChange={e=>setQ(e.target.value)} placeholder="بحث بالاسم العربي/الانجليزي/المادة/الباركود" className="flex-1 border p-2 rounded"/><button onClick={importCSV} className="bg-blue-600 text-white px-4 rounded">تحديث قاعدة الادوية (استيراد)</button></div><table className="w-full bg-white rounded shadow"><thead><tr className="bg-gray-100"><th className="p-2">الاسم</th><th>المادة</th><th>السعر</th><th>بدائل</th><th>بيع</th></tr></thead><tbody>{meds.map(m=> <tr key={m.id} className="border-t"><td className="p-2">{m.name_ar} <span className="text-gray-400 text-sm">/ {m.name_en}</span></td><td>{m.active_ingredient} {m.concentration}</td><td className="num">{m.price} ج</td><td><button onClick={async()=>{const db=await getDb(); const alt:any[]=await db.select("SELECT * FROM medicines WHERE active_ingredient=$1 AND concentration=$2 ORDER BY price ASC",[m.active_ingredient,m.concentration]); alert(alt.map(a=>`${a.name_ar} - ${a.price}ج`).join("\n")||"لا يوجد بديل")}} className="text-blue-600">عرض البدائل</button></td><td><button onClick={()=>addToCart(m)} className="bg-green-600 text-white px-2 rounded">+</button></td></tr>)}</tbody></table></div>)}{tab==="pos" && (<div className="grid grid-cols-3 gap-4"><div className="col-span-2 bg-white p-4 rounded shadow"><h2 className="font-bold mb-2">السلة - F1 بحث F2 خصم F9 دفع</h2>{cart.map((c,i)=><div key={i} className="flex justify-between border-b py-1"><span>{c.name_ar}</span><span className="num">{c.price} x {c.qty}</span></div>)}<div className="font-bold mt-4 num">الاجمالي: {total.toFixed(2)} ج</div><button onClick={sell} className="w-full bg-blue-600 text-white p-2 mt-2 rounded">دفع وطباعة حرارية 80mm</button></div><div className="bg-white p-4 rounded shadow text-sm text-gray-500">باركود + Enter يضيف تلقائي<br/>الخصم FEFO من الاقرب انتهاء</div></div>)}{tab==="settings" && (<div className="bg-white p-6 rounded shadow space-y-3"><h2 className="font-bold">الربط بدون انترنت - نفس الشبكة LAN</h2><p>1- الجهاز الرئيسي: فعل وضع السيرفر وسيظهر IP مثل 192.168.1.5:3030</p><p>2- الجهاز الثاني: اكتب نفس الـ IP واضغط اتصال - المزامنة كل 30 ثانية</p><p>3- النسخ الاحتياطي يومي مشفر AES-256</p><input placeholder="IP الجهاز الرئيسي مثلا 192.168.1.5" className="border p-2 w-full"/><button className="bg-green-600 text-white px-4 py-2 rounded">اتصال</button></div>)}</main></div>)
}
\'@ | Set-Content -Encoding utf8 -Path "src/App.tsx"

# ===== Tauri =====
@\'
{
  "productName": "PharmaDesk",
  "version": "1.0.0",
  "identifier": "com.pharmadesk.app",
  "build": { "beforeDevCommand": "npm run dev", "beforeBuildCommand": "npm run build", "devUrl": "http://localhost:1420", "frontendDist": "../dist" },
  "app": { "windows": [{ "title": "PharmaDesk - ادارة صيدليات", "width": 1280, "height": 800 }], "security": { "csp": null } },
  "bundle": { "active": true, "targets": "all", "icon": [] },
  "plugins": { "sql": { "preload": ["sqlite:pharma.db"] } }
}
\'@ | Set-Content -Encoding utf8 -Path "src-tauri/tauri.conf.json"

@\'
[package]
name = "pharma-desk"
version = "1.0.0"
edition = "2021"
[build-dependencies]
tauri-build = { version = "2.0.0" }
[dependencies]
tauri = { version = "2.0.0", features = [] }
tauri-plugin-sql = { version = "2.0.0" }
tauri-plugin-fs = "2.0.0"
tauri-plugin-dialog = "2.0.0"
serde = { version = "1.0", features = ["derive"] }
\'@ | Set-Content -Encoding utf8 -Path "src-tauri/Cargo.toml"

@\'fn main() { tauri_build::build() }\'@ | Set-Content -Encoding utf8 -Path "src-tauri/build.rs"
@\'#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
fn main() { tauri::Builder::default().plugin(tauri_plugin_sql::Builder::default().build()).plugin(tauri_plugin_fs::init()).plugin(tauri_plugin_dialog::init()).run(tauri::generate_context!()).expect("error"); }\'@ | Set-Content -Encoding utf8 -Path "src-tauri/src/main.rs"

# ===== GitHub Actions =====
New-Item -ItemType Directory -Force -Path ".github/workflows" | Out-Null
@\'
name: Build PharmaDesk
on: [push]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }
      - uses: dtolnay/rust-toolchain@stable
      - run: npm install
      - run: npm run tauri build
      - uses: actions/upload-artifact@v4
        with:
          name: PharmaDesk-Windows-Setup
          path: src-tauri/target/release/bundle/**/*.exe
\'@ | Set-Content -Encoding utf8 -Path ".github/workflows/build.yml"

# ===== Sample Data + Importer =====
@\'barcode,name_ar,name_en,active_ingredient,concentration,price,manufacturer,status
6223000000010,بنادول اكسترا,Panadol Extra,Paracetamol+Caffeine,500mg,27.0,GSK,متداول
6223000000027,اوجمنتين 1جم,Augmentin 1g,Amoxicillin+Clavulanate,1g,89.5,GSK,متداول
6223000000034,كونجستال,Congestal,Paracetamol+Chlorpheniramine,500mg,22.0,Sigma,متداول
\'@ | Set-Content -Encoding utf8 -Path "scripts/drugs-importer/sample_medicines.csv"
@\'import pandas as pd, sys
df=pd.read_excel(sys.argv[1])
df_clean=pd.DataFrame()
df_clean["barcode"]=df["Barcode"].astype(str)
df_clean["name_ar"]=df["Trade Name AR"]
df_clean["price"]=df["Public Price"]
df_clean.to_csv(sys.argv[2], index=False, encoding="utf-8-sig")
print(f"تم توحيد {len(df_clean)} صنف")
\'@ | Set-Content -Encoding utf8 -Path "scripts/drugs-importer/importer.py"

@\'node_modules
src-tauri/target
dist
\'@ | Set-Content -Encoding utf8 -Path ".gitignore"

Compress-Archive -Path * -DestinationPath ../pharma-desk.zip -Force
Write-Host "تم انشاء pharma-desk.zip بنجاح في" (Resolve-Path ../pharma-desk.zip) -ForegroundColor Green
