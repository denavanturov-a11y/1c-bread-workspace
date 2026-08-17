"use client";

import { ChangeEvent, useMemo, useRef, useState } from "react";

type Screen = "upload" | "processing" | "review" | "sending" | "done" | "duplicate";

type Row = {
  id: number;
  sourceName: string;
  productId: string;
  quantity: number;
  purchasePrice: number;
  retailPrice: number;
  minMarkup: number;
  needsReview: boolean;
};

const products = [
  { id: "bread-borodino", name: "Хлеб Бородинский 400 г", code: "000341" },
  { id: "bread-darnitsa", name: "Хлеб Дарницкий формовой", code: "001960" },
  { id: "baton-sliced", name: "Батон нарезной 400 г", code: "000098" },
  { id: "bun-moscow", name: "Булочка Московская 100 г", code: "005357" },
  { id: "bun-home", name: "Булочка Домашняя 90 г", code: "012407" },
];

const initialRows: Row[] = [
  { id: 1, sourceName: "Хлеб Бород. новый 0,4", productId: "bread-borodino", quantity: 8, purchasePrice: 61, retailPrice: 86, minMarkup: 38, needsReview: false },
  { id: 2, sourceName: "Хлеб Дарницкий форм.", productId: "bread-darnitsa", quantity: 10, purchasePrice: 63, retailPrice: 90, minMarkup: 40, needsReview: false },
  { id: 3, sourceName: "Батон нарез. в/с 400", productId: "baton-sliced", quantity: 12, purchasePrice: 58, retailPrice: 82, minMarkup: 40, needsReview: true },
  { id: 4, sourceName: "Булочка Московская", productId: "bun-moscow", quantity: 15, purchasePrice: 32, retailPrice: 45, minMarkup: 35, needsReview: false },
  { id: 5, sourceName: "Булочка Домаш. 90", productId: "", quantity: 10, purchasePrice: 29, retailPrice: 42, minMarkup: 35, needsReview: false },
];

function money(value: number) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB", maximumFractionDigits: 2 }).format(value);
}

function markup(row: Row) {
  return row.purchasePrice > 0 ? ((row.retailPrice / row.purchasePrice - 1) * 100) : 0;
}

export default function Home() {
  const [screen, setScreen] = useState<Screen>("upload");
  const [rows, setRows] = useState<Row[]>(initialRows);
  const [fileName, setFileName] = useState("");
  const [previewUrl, setPreviewUrl] = useState("");
  const fileInput = useRef<HTMLInputElement>(null);

  const totals = useMemo(() => ({
    units: rows.reduce((sum, row) => sum + Number(row.quantity || 0), 0),
    purchase: rows.reduce((sum, row) => sum + Number(row.quantity || 0) * Number(row.purchasePrice || 0), 0),
  }), [rows]);

  const issues = rows.filter((row) => !row.productId || row.needsReview || markup(row) < row.minMarkup);
  const canApprove = issues.length === 0;

  function beginRecognition(file?: File) {
    if (file) {
      setFileName(file.name);
      setPreviewUrl(URL.createObjectURL(file));
    } else {
      setFileName("Тестовая_накладная_Хлебозавод_№3.jpg");
      setPreviewUrl("");
    }
    setRows(initialRows);
    setScreen("processing");
    window.setTimeout(() => setScreen("review"), 950);
  }

  function handleFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (file) beginRecognition(file);
  }

  function patchRow(id: number, patch: Partial<Row>) {
    setRows((current) => current.map((row) => row.id === id ? { ...row, ...patch } : row));
  }

  function approve() {
    if (!canApprove) return;
    setScreen("sending");
    window.setTimeout(() => setScreen("done"), 900);
  }

  function reset() {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
    setPreviewUrl("");
    setFileName("");
    setRows(initialRows);
    setScreen("upload");
    if (fileInput.current) fileInput.current.value = "";
  }

  const step = screen === "upload" || screen === "processing" ? 1 : screen === "review" ? 2 : 3;

  return (
    <main className="app-shell">
      <header className="topbar">
        <button className="brand" type="button" onClick={reset} aria-label="Хлеб.Приход — начать заново">
          <span className="brand-mark" aria-hidden="true">Х</span>
          <span>Хлеб.Приход</span>
        </button>
        <div className="topbar-actions">
          <span className="safe-state"><i /> 1С не подключена</span>
          <div className="demo-badge"><span /> Демо</div>
        </div>
      </header>

      <div className={`page-frame ${screen === "review" ? "wide" : ""}`}>
        <ol className="steps" aria-label="Этапы обработки">
          {["Фото", "Проверка", "Готово"].map((label, index) => {
            const number = index + 1;
            return <li key={label} className={number === step ? "active" : number < step ? "complete" : ""}>
              <span>{number < step ? "✓" : number}</span><b>{label}</b>
            </li>;
          })}
        </ol>

        {screen === "upload" && (
          <section className="screen screen-upload">
            <div className="intro">
              <p className="eyebrow">Новая поставка</p>
              <h1>Добавьте накладную</h1>
              <p>Сфотографируйте документ — подготовим товары и цены для проверки.</p>
            </div>
            <section className="upload-card">
              <div className="document-visual" aria-hidden="true">
                <div className="document-sheet"><i /><i /><i /><i /></div>
                <span className="camera-dot">●</span>
              </div>
              <h2>Сфотографируйте накладную</h2>
              <p>Положите документ на ровную поверхность. Все края должны быть видны.</p>
              <input ref={fileInput} className="visually-hidden" type="file" accept="image/*" capture="environment" onChange={handleFile} />
              <button className="primary-button" type="button" onClick={() => fileInput.current?.click()}>
                <span aria-hidden="true">＋</span> Добавить фото
              </button>
              <div className="or"><span>или</span></div>
              <button className="secondary-button" type="button" onClick={() => beginRecognition()}>
                Открыть тестовую накладную
              </button>
            </section>
            <aside className="privacy-note">
              <span aria-hidden="true">✓</span>
              <div><b>Безопасный прототип</b><p>Фото остаётся в браузере. Рабочая база 1С не используется.</p></div>
            </aside>
          </section>
        )}

        {screen === "processing" && (
          <section className="screen processing-card" aria-live="polite">
            <div className="scan-preview">
              {previewUrl ? (
                /* eslint-disable-next-line @next/next/no-img-element -- local blob URL preview */
                <img src={previewUrl} alt="Загруженная накладная" />
              ) : <div className="mock-invoice"><b>НАКЛАДНАЯ</b><i /><i /><i /><i /><i /></div>}
              <span className="scan-line" />
            </div>
            <p className="eyebrow">Демонстрация</p>
            <h1>Готовим данные</h1>
            <p>Определяем поставщика, товары, количество и закупочные цены…</p>
            <div className="loader"><i /><i /><i /></div>
          </section>
        )}

        {screen === "review" && (
          <section className="screen review-screen">
            <div className="review-heading">
              <div>
                <p className="eyebrow">Проверка накладной</p>
                <h1>Хлебозавод № 3</h1>
                <p>Накладная № 184 · 16 августа 2026 · {fileName}</p>
              </div>
              <button className="text-button" type="button" onClick={reset}>Начать заново</button>
            </div>

            <div className="prototype-warning"><b>Это демонстрация.</b> Данные ниже тестовые — реальное распознавание и подключение к 1С появятся на следующем этапе.</div>

            <div className="summary-grid">
              <div><span>Позиций</span><b>{rows.length}</b></div>
              <div><span>Количество</span><b>{totals.units} шт.</b></div>
              <div><span>Сумма закупки</span><b>{money(totals.purchase)}</b></div>
              <div className={issues.length ? "attention" : "ok"}><span>Требуют внимания</span><b>{issues.length}</b></div>
            </div>

            <div className="table-card">
              <div className="table-title">
                <div><h2>Товарные строки</h2><p>Проверьте сопоставление, количество и цену продажи</p></div>
                <span className="legend"><i /> изменения сохраняются в этой демонстрации</span>
              </div>
              <div className="invoice-table">
                <div className="table-header">
                  <span>Из накладной / товар в 1С</span><span>Кол-во</span><span>Закупка</span><span>Розница</span><span>Наценка</span>
                </div>
                {rows.map((row) => {
                  const currentMarkup = markup(row);
                  const lowMarkup = currentMarkup < row.minMarkup;
                  return (
                    <div className={`product-row ${!row.productId ? "row-error" : row.needsReview || lowMarkup ? "row-warning" : ""}`} key={row.id}>
                      <div className="product-cell">
                        <span className="source-name">{row.sourceName}</span>
                        <label>
                          <span className="mobile-label">Товар в 1С</span>
                          <select aria-label={`Товар в 1С для строки ${row.sourceName}`} value={row.productId} onChange={(event) => patchRow(row.id, { productId: event.target.value })}>
                            <option value="">Выберите товар в 1С…</option>
                            {products.map((product) => <option key={product.id} value={product.id}>{product.name} · {product.code}</option>)}
                          </select>
                        </label>
                        {!row.productId && <small className="error-text">Товар не сопоставлен</small>}
                        {row.needsReview && <button className="confirm-line" type="button" onClick={() => patchRow(row.id, { needsReview: false })}>Проверить строку → подтвердить</button>}
                      </div>
                      <label className="number-cell"><span className="mobile-label">Количество</span><input aria-label={`Количество: ${row.sourceName}`} type="number" min="0" step="1" value={row.quantity} onChange={(event) => patchRow(row.id, { quantity: Number(event.target.value) })} /><em>шт.</em></label>
                      <label className="number-cell"><span className="mobile-label">Закупка</span><input aria-label={`Закупочная цена: ${row.sourceName}`} type="number" min="0" step="0.01" value={row.purchasePrice} onChange={(event) => patchRow(row.id, { purchasePrice: Number(event.target.value) })} /><em>₽</em></label>
                      <label className="number-cell retail"><span className="mobile-label">Розничная цена</span><input aria-label={`Розничная цена: ${row.sourceName}`} type="number" min="0" step="1" value={row.retailPrice} onChange={(event) => patchRow(row.id, { retailPrice: Number(event.target.value) })} /><em>₽</em></label>
                      <div className={`markup-cell ${lowMarkup ? "low" : ""}`}><b>{currentMarkup.toFixed(1)}%</b><span>мин. {row.minMarkup}%</span>{lowMarkup && <small>Ниже минимума</small>}</div>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="approval-bar">
              <div>
                <span>Итого к оприходованию</span>
                <b>{totals.units} шт. · {money(totals.purchase)}</b>
                {issues.length > 0 && <small>Исправьте или подтвердите ещё {issues.length} {issues.length === 1 ? "строку" : "строки"}</small>}
              </div>
              <button className="approve-button" type="button" disabled={!canApprove} onClick={approve}>Согласовать и продолжить <span>→</span></button>
            </div>
          </section>
        )}

        {screen === "sending" && (
          <section className="screen processing-card" aria-live="polite">
            <div className="connector-animation"><span>Веб</span><i /><span>1С</span></div>
            <p className="eyebrow">Имитация интеграции</p>
            <h1>Передаём в 1С</h1>
            <p>Проверяем данные и создаём тестовый документ поступления…</p>
            <div className="loader"><i /><i /><i /></div>
          </section>
        )}

        {screen === "done" && (
          <section className="screen done-card">
            <div className="success-mark">✓</div>
            <p className="eyebrow">Демонстрация завершена</p>
            <h1>Накладная согласована</h1>
            <p>В рабочей версии после этого шага документ будет создан в 1С, а штатный обмен передаст цены на кассу.</p>
            <div className="receipt">
              <div><span>Документ</span><b>ПТ-000184 <em>имитация</em></b></div>
              <div><span>Поставщик</span><b>Хлебозавод № 3</b></div>
              <div><span>Товаров</span><b>{rows.length} позиций · {totals.units} шт.</b></div>
              <div><span>Сумма</span><b>{money(totals.purchase)}</b></div>
              <div><span>Статус</span><b className="green-text">Готово к передаче в 1С</b></div>
            </div>
            <button className="primary-button" type="button" onClick={reset}>Загрузить другую накладную</button>
            <button className="demo-link" type="button" onClick={() => setScreen("duplicate")}>Проверить защиту от повторной загрузки</button>
          </section>
        )}

        {screen === "duplicate" && (
          <section className="screen duplicate-card">
            <div className="warning-mark">!</div>
            <p className="eyebrow">Защита от дублей</p>
            <h1>Похожая накладная уже обработана</h1>
            <p>Совпали поставщик, дата, позиции, количество и сумма. Система не создаст второе поступление без явного решения.</p>
            <div className="duplicate-reference"><span>Найденный документ</span><b>ПТ-000184 · 16 августа 2026</b></div>
            <button className="primary-button" type="button" onClick={() => setScreen("done")}>Вернуться к результату</button>
          </section>
        )}
      </div>
    </main>
  );
}
