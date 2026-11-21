// Gera relatorio/Relatorio-Livraria-Nuvem.docx a partir de relatorio/RELATORIO.md.
// Rodar: bash relatorio/word/gerar.sh  (node + docx num container; o PDF sai pelo Microsoft Word)
const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, ImageRun, PageBreak, Header, Footer, PageNumber,
  TableOfContents, LevelFormat, TabStopType,
} = require("docx");

const ROOT = path.resolve(__dirname, "..");
const MD = fs.readFileSync(path.join(ROOT, "RELATORIO.md"), "utf8");
const OUT = path.join(ROOT, "Relatorio-Livraria-Nuvem.docx");

const FONT = "Arial";
const AZUL = "000000", AZUL_CLARO = "A6A6A6", CINZA = "595959", VERMELHO = "404040", CAB_TAB = "E7E6E6";
const PAGE_W = 11906, MARGIN = 1134;            // A4, margens de 2 cm
const CONTENT_W = PAGE_W - 2 * MARGIN;          // 9638 DXA = 17 cm
const MAX_IMG_PX = 640;                          // largura máxima da imagem (px a 96 dpi ~ 16,9 cm)

// ---------- texto inline: **negrito**, `código`, [texto](link) ----------
function runs(text, base = {}) {
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, "$1");
  const out = [];
  const re = /(\*\*[^*]+\*\*|`[^`]+`|(?<![\w*])\*[^*\s][^*]*\*(?![\w*]))/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(new TextRun({ text: text.slice(last, m.index), ...base }));
    const t = m[0];
    if (t.startsWith("**")) {
      // negrito pode conter `codigo`
      const inner = t.slice(2, -2);
      inner.split(/(`[^`]+`)/).filter(Boolean).forEach((p) =>
        out.push(p.startsWith("`")
          ? new TextRun({ text: p.slice(1, -1), bold: true, color: "262626", ...base })
          : new TextRun({ text: p, bold: true, ...base })));
    } else if (t.startsWith("*")) {
      out.push(new TextRun({ text: t.slice(1, -1), italics: true, ...base }));
    } else {
      out.push(new TextRun({ text: t.slice(1, -1), color: "262626", ...base }));
    }
    last = m.index + t.length;
  }
  if (last < text.length) out.push(new TextRun({ text: text.slice(last), ...base }));
  return out;
}

// ---------- imagens ----------
function pngSize(buf) { return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) }; }
let figN = 0;
function figure(caption, rel) {
  const file = path.resolve(ROOT, rel);
  const buf = fs.readFileSync(file);
  const { w, h } = pngSize(buf);
  const width = MAX_IMG_PX, height = Math.round((h / w) * MAX_IMG_PX);
  const maxH = 520;                                    // evita figura maior que meia página
  const k = height > maxH ? maxH / height : 1;
  figN += 1;
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 160, after: 60 },
      children: [new ImageRun({ type: "png", data: buf,
        transformation: { width: Math.round(width * k), height: Math.round(height * k) },
        altText: { title: `Figura ${figN}`, description: caption, name: `Figura ${figN}` } })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { after: 220 },
      children: [new TextRun({ text: `Figura ${figN} – `, bold: true, size: 18, color: CINZA, font: FONT }),
        ...runs(caption, { italics: true, size: 18, color: CINZA })],
    }),
  ];
}

// ---------- tabelas ----------
const border = { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF" };
const borders = { top: border, bottom: border, left: border, right: border };
function table(rows) {
  const cells = rows.map((r) => r.replace(/^\||\|$/g, "").split("|").map((c) => c.trim()));
  const header = cells[0];
  const body = cells.slice(2);                         // pula a linha |---|
  const n = header.length;
  // largura proporcional ao texto (mínimo 12%)
  const lens = header.map((_, i) => Math.max(...[header, ...body].map((r) => (r[i] || "").length), 4));
  const tot = lens.reduce((a, b) => a + b, 0);
  let widths = lens.map((l) => Math.max(Math.round((l / tot) * CONTENT_W), Math.round(CONTENT_W * 0.12)));
  const sum = widths.reduce((a, b) => a + b, 0);
  widths = widths.map((x) => Math.round((x * CONTENT_W) / sum));
  widths[n - 1] += CONTENT_W - widths.reduce((a, b) => a + b, 0);
  const mk = (r, head) => new TableRow({
    tableHeader: head, cantSplit: true,
    children: r.map((c, i) => new TableCell({
      borders, width: { size: widths[i], type: WidthType.DXA },
      shading: head ? { fill: CAB_TAB, type: ShadingType.CLEAR, color: "auto" } : undefined,
      margins: { top: 60, bottom: 60, left: 100, right: 100 },
      children: [new Paragraph({ spacing: { before: 0, after: 0, line: 252 },
        children: runs(c || "", head ? { bold: true, color: "000000", size: 18 } : { size: 18 }) })],
    })),
  });
  return [new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: widths,
    rows: [mk(header, true), ...body.map((r) => mk(r, false))] }),
    new Paragraph({ spacing: { after: 120 }, children: [] })];
}

// ---------- capa ----------
function capa() {
  const p = (text, opt = {}) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: opt.after ?? 120 },
    children: [new TextRun({ text, font: FONT, ...opt })] });
  return [
    new Paragraph({ spacing: { before: 2200 }, children: [] }),
    p("INSPER · COMPUTAÇÃO EM NUVEM", { size: 22, color: CINZA, bold: true, after: 400 }),
    p("Livraria Nuvem", { size: 64, bold: true, color: AZUL, after: 160 }),
    p("Comércio conversacional na AWS", { size: 34, color: AZUL, after: 600 }),
    new Paragraph({ alignment: AlignmentType.CENTER, border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: VERMELHO, space: 1 } },
      spacing: { after: 600 }, children: [] }),
    p("Relatório técnico do projeto semestral", { size: 28, after: 200 }),
    p("Parte 1: Ohio (us-east-2), montagem manual", { size: 24, color: CINZA, after: 60 }),
    p("Parte 2: São Paulo (sa-east-1), Terraform", { size: 24, color: CINZA, after: 1600 }),
    p("Grupo: Ana Clara · João · Lara · Maria Eduarda · Pedro", { size: 22, after: 80 }),
    p("Repositório: github.com/palmeidav/projeto-cc", { size: 20, color: CINZA, after: 80 }),
    p("Novembro de 2026", { size: 20, color: CINZA }),
    new Paragraph({ children: [new PageBreak()] }),
    new Paragraph({ spacing: { after: 200 }, children: [new TextRun({ text: "Sumário", bold: true, size: 30, color: "000000", font: FONT })] }),
    new TableOfContents("Sumário", { hyperlink: true, headingStyleRange: "1-2" }),
    new Paragraph({ children: [new PageBreak()] }),
  ];
}

// ---------- conversão do markdown ----------
const children = capa();
const lines = MD.split("\n");
let i = 0, firstH1 = true, para = [];
const flushPara = () => {
  if (para.length) children.push(new Paragraph({ alignment: AlignmentType.JUSTIFIED, spacing: { after: 160 }, children: runs(para.join(" ")) }));
  para = [];
};
let firstH2 = true;
let listInst = 0, inList = false;
while (i < lines.length) {
  const raw = lines[i];
  const line = raw.trimEnd();
  // título e linhas de capa (já estão na capa)
  if (/^# /.test(line) && firstH1) { firstH1 = false; i++; continue; }
  if (/^\*\*Projeto semestral/.test(line) || /^Repositório:/.test(line)) { i++; continue; }
  if (/^> /.test(line)) { i++; continue; }
  if (line === "---" ) { flushPara(); i++; continue; }
  if (line === "") { flushPara(); i++; continue; }
  let m;
  if ((m = line.match(/^## (.*)/))) {
    flushPara();
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: !firstH2, children: [new TextRun(m[1])] }));
    firstH2 = false; i++; continue;
  }
  if ((m = line.match(/^### (.*)/))) {
    flushPara();
    children.push(new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(m[1])] }));
    i++; continue;
  }
  if ((m = line.match(/^!\[([^\]]*)\]\(([^)]+)\)/))) { flushPara(); children.push(...figure(m[1], m[2])); i++; continue; }
  if (line.startsWith("```")) {
    flushPara(); i++;
    while (i < lines.length && !lines[i].startsWith("```")) {
      children.push(new Paragraph({ spacing: { after: 0 }, shading: { fill: "F2F2F2", type: ShadingType.CLEAR, color: "auto" },
        children: [new TextRun({ text: lines[i] || " ", font: FONT, size: 18 })] }));
      i++;
    }
    i++; continue;
  }
  if (/^\s*\|/.test(line)) {
    flushPara();
    const rows = [];
    while (i < lines.length && /^\s*\|/.test(lines[i])) { rows.push(lines[i].trim()); i++; }
    children.push(...table(rows));
    continue;
  }
  const bul = line.match(/^(\s*)([-*]|\d+\.) (.*)/);
  if (!bul && line.trim() !== "") inList = false;
  if (bul) {
    flushPara();
    if (!inList) { listInst += 1; inList = true; }
    const level = Math.min(Math.floor(bul[1].length / 2), 2);
    const numbered = /\d+\./.test(bul[2]);
    let text = bul[3]; i++;
    // linhas de continuação (indentadas, que não começam outro item nem tabela/imagem)
    while (i < lines.length && /^\s{2,}\S/.test(lines[i]) && !/^\s*([-*]|\d+\.) /.test(lines[i]) && !/^\s*\|/.test(lines[i])) {
      text += " " + lines[i].trim(); i++;
    }
    children.push(new Paragraph({ numbering: { reference: numbered ? "num" : "bul", level, instance: listInst }, alignment: AlignmentType.JUSTIFIED, spacing: { after: 80 }, children: runs(text) }));
    continue;
  }
  // tabela indentada dentro de item de lista
  para.push(line.trim()); i++;
}
flushPara();

const doc = new Document({
  creator: "Grupo Livraria Nuvem", title: "Livraria Nuvem: relatório técnico",
  description: "Projeto semestral de Computação em Nuvem (Insper)",
  styles: {
    default: { document: { run: { font: FONT, size: 22 }, paragraph: { spacing: { line: 312 } } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 30, bold: true, color: "000000" },
        paragraph: { spacing: { before: 240, after: 160 }, keepNext: true, outlineLevel: 0,
          border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: AZUL_CLARO, space: 4 } } } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: FONT, size: 24, bold: true, color: "000000" },
        paragraph: { spacing: { before: 200, after: 100 }, keepNext: true, outlineLevel: 1 } },
    ],
  },
  numbering: { config: [
    { reference: "bul", levels: [0, 1, 2].map((l) => ({ level: l, format: LevelFormat.BULLET, text: ["•", "–", "▪"][l],
      alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360 + 360 * l, hanging: 260 } } } })) },
    { reference: "num", levels: [0, 1, 2].map((l) => ({ level: l, format: LevelFormat.DECIMAL, text: `%${l + 1}.`,
      alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360 + 360 * l, hanging: 300 } } } })) },
  ] },
  sections: [{
    properties: { page: { size: { width: PAGE_W, height: 16838 }, margin: { top: MARGIN, bottom: MARGIN, left: MARGIN, right: MARGIN } },
      titlePage: true },
    headers: {
      default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
        border: { bottom: { style: BorderStyle.SINGLE, size: 4, color: "BFBFBF", space: 2 } },
        children: [new TextRun({ text: "Livraria Nuvem · Relatório técnico", size: 16, color: CINZA })] })] }),
      first: new Header({ children: [new Paragraph({ children: [] })] }),
    },
    footers: {
      default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
        children: [new TextRun({ children: ["Página ", PageNumber.CURRENT, " de ", PageNumber.TOTAL_PAGES], size: 16, color: CINZA })] })] }),
      first: new Footer({ children: [new Paragraph({ children: [] })] }),
    },
    children,
  }],
});

Packer.toBuffer(doc).then((b) => { fs.writeFileSync(OUT, b); console.log(`gerado: ${OUT} (${figN} figuras)`); });
