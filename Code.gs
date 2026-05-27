// Nexus Relatórios – Clean Apps Script

// ---------- Utilities ----------
function resposta(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function getSpreadsheet() {
  return SpreadsheetApp.getActiveSpreadsheet();
}

// Sheet getters handling name variations
function getRelatoriosSheet(ss) {
  const names = ['RELATORIOS', 'Relatorios', 'Relatórios', 'RELATÓRIOS'];
  for (const n of names) {
    const sh = ss.getSheetByName(n);
    if (sh) return sh;
  }
  return null;
}

function getOrCreateRelatoriosSheet(ss) {
  let sh = getRelatoriosSheet(ss);
  if (!sh) sh = ss.insertSheet('RELATORIOS');
  return sh;
}

function getEscolasSheet(ss) {
  const sh = ss.getSheetByName('Escolas');
  return sh ? sh : null;
}

function getTecnicosSheet(ss) {
  const sh = ss.getSheetByName('Técnicos');
  if (sh) return sh;
  // fallback to possible older names
  const alt = ss.getSheetByName('Tecnicos') || ss.getSheetByName('tecnicos');
  return alt;
}

function getHistoricoSheet(ss) {
  const sh = ss.getSheetByName('historico_relatorios');
  if (sh) return sh;
  // create if missing
  return ss.insertSheet('historico_relatorios');
}

const RELATORIOS_HEADERS = [
  'Data do Envio',
  'ID do Relatório',
  'Usuário Logado',
  'Nome da Escola',
  'Data da Visita',
  'Tipo de Relatório',
  'Motivos / Assuntos',
  'Técnicos Presentes',
  'Responsável da Escola',
  'Observações',
  'Link Assinatura',
  'Link Foto',
  'Número do Relatório',
  'Regional (GRE)',
  'municipio',
  'Endereço da Escola',
  'inep',
  'fotos_json'
];

function ensureHeaders(sheet, headers) {
  const current = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  const missing = [];
  headers.forEach(h => { if (!current.includes(h)) missing.push(h); });
  if (missing.length) {
    const startCol = current.length + 1;
    sheet.getRange(1, startCol, 1, missing.length).setValues([missing]);
  }
}

function normalizeListField(value) {
  if (Array.isArray(value)) return value.join(', ');
  if (typeof value === 'string') return value.trim();
  return '';
}

function splitList(value) {
  if (Array.isArray(value)) return value.map(v => String(v).trim()).filter(v => v);
  if (typeof value === 'string') {
    return value.split(/[,;\n]/).map(v => v.trim()).filter(v => v);
  }
  return [];
}

function parseFotosJsonForClient(fotosJsonStr, linkFotoStr) {
  const photos = [];
  // try json string first
  if (fotosJsonStr) {
    try {
      const arr = JSON.parse(fotosJsonStr);
      if (Array.isArray(arr)) {
        arr.forEach(item => {
          if (item && typeof item === 'object') {
            photos.push({
              path: item.path || '',
              url: item.url || '',
              comment: item.comment || ''
            });
          }
        });
      }
    } catch (e) { /* ignore */ }
  }
  // fallback to linkFoto (may be a single URL or comma‑separated list)
  if (linkFotoStr) {
    const parts = splitList(linkFotoStr);
    parts.forEach(p => {
      if (p && !photos.find(ph => ph.url === p)) {
        photos.push({ path: '', url: p, comment: '' });
      }
    });
  }
  return photos;
}

function resolveMunicipioFromReport(rowMap, escolasSheet) {
  // rowMap is an object where keys are header names
  if (rowMap['municipio'] && rowMap['municipio'].toString().trim()) return rowMap['municipio'];
  const inep = rowMap['inep'] || rowMap['INEP'];
  if (escolasSheet && inep) {
    const data = escolasSheet.getDataRange().getValues();
    const header = data[0];
    const idxInep = header.indexOf('INEP');
    const idxMunicipio = header.indexOf('MUNICIPIO');
    const idxNome = header.indexOf('NOME');
    for (let i = 1; i < data.length; i++) {
      const r = data[i];
      if (String(r[idxInep]).trim() === String(inep).trim()) {
        return r[idxMunicipio] || '';
      }
    }
    // fallback by school name
    const nomeEscola = rowMap['Nome da Escola'];
    if (nomeEscola) {
      for (let i = 1; i < data.length; i++) {
        const r = data[i];
        if (String(r[idxNome]).trim() === String(nomeEscola).trim()) {
          return r[idxMunicipio] || '';
        }
      }
    }
  }
  return '';
}

function uploadBase64ToDrive(base64Str, folder, filename) {
  const contentTypeMatch = base64Str.match(/^data:(image\/\w+);base64,/);
  let contentType = 'image/png';
  let data = base64Str;
  if (contentTypeMatch) {
    contentType = contentTypeMatch[1];
    data = base64Str.split(',')[1];
  }
  const bytes = Utilities.base64Decode(data);
  const blob = Utilities.newBlob(bytes, contentType, filename);
  const file = folder.createFile(blob);
  return "https://drive.google.com/uc?export=download&id=" + file.getId();
}

// ---------- Router ----------
function doGet(e) {
  // simple health check
  return resposta({ status: 'success', success: true, message: 'Apps Script is alive' });
}

function doPost(e) {
  let payload = {};
  try {
    const body = e.postData.contents;
    payload = JSON.parse(body);
  } catch (err) {
    return resposta({ status: 'error', success: false, message: 'Invalid JSON' });
  }
  const action = payload.action || payload.acao;
  if (!action) {
    return resposta({ status: 'error', success: false, message: 'Missing action' });
  }
  const act = action.toString().toLowerCase();
  const ss = getSpreadsheet();
  switch (act) {
    case 'login':
      return loginAction(payload.payload || {});
    case 'checar_versao':
    case 'checkversion':
    case 'check_version':
    case 'checkversionaction':
      return checkVersionAction(payload.payload || {});
    case 'buscar_relatorios':
    case 'fetchreports':
    case 'fetchreportsaction':
      return fetchReportsAction(payload.payload || {});
    case 'adicionar':
    case 'sendreport':
    case 'savereport':
    case 'savereportaction':
      return saveReportAction(payload.payload || {});
    case 'deletar_relatorio':
    case 'deletereport':
    case 'deletereportaction':
      return deleteReportAction(payload.payload || {});
    case 'buscar_escolas':
    case 'fetchschools':
    case 'fetchschoolsaction':
      return fetchSchoolsAction(payload.payload || {});
    case 'buscar_tecnicos':
    case 'fetchtechnicians':
    case 'fetchtechniciansaction':
      return fetchTechniciansAction(payload.payload || {});
    case 'buscar_historico':
    case 'fetchhistory':
    case 'fetchhistoryaction':
      return fetchHistoryAction(payload.payload || {});
    case 'corrigirmunicipiosrelatorios':
    case 'corrigirmunicipiosrelatoriosaction':
      return corrigirMunicipiosRelatoriosAction(payload.payload || {});
    case 'corrigirrelatoriosduplicados':
    case 'corrigirrelatoriosduplicadosaction':
      return corrigirRelatoriosDuplicadosAction(payload.payload || {});
    default:
      return resposta({ status: 'error', success: false, message: 'Unknown action: ' + action });
  }
}

// ---------- Action Implementations ----------
function loginAction(p) {
  const email = (p.email || p.emailUser || '').toString().trim().toLowerCase();
  const senha = (p.password || p.senha || '').toString();
  const techSheet = getTecnicosSheet(getSpreadsheet());
  if (!techSheet) return resposta({ status: 'error', success: false, message: 'Tecnicos sheet not found' });
  const data = techSheet.getDataRange().getValues();
  const header = data[0];
  const idxEmail = header.indexOf('EMAIL');
  const idxSenha = header.indexOf('SENHA');
  const idxId = header.indexOf('ID');
  const idxNome = header.indexOf('NOME');
  const idxMat = header.indexOf('MATRICULA');
  const idxPerm = header.indexOf('PERMISSAO');
  for (let i = 1; i < data.length; i++) {
    const row = data[i];
    if (String(row[idxEmail]).trim().toLowerCase() === email && String(row[idxSenha]) === senha) {
      const tecnico = {
        id: row[idxId] || '',
        nome: row[idxNome] || '',
        matricula: row[idxMat] || '',
        email: row[idxEmail] || '',
        permissao: row[idxPerm] || ''
      };
      return resposta({ status: 'success', success: true, tecnico });
    }
  }
  return resposta({ status: 'error', success: false, message: 'Invalid credentials' });
}

function checkVersionAction(p) {
  // static version – adjust if you store elsewhere
  const version = '2.1.2';
  const result = {
    status: 'success',
    success: true,
    versao: version,
    android: { versao: version, link: '' },
    windows: { versao: version, link: '' },
    link_android: '',
    link_windows: ''
  };
  return resposta(result);
}

function fetchReportsAction(p) {
  const ss = getSpreadsheet();
  const sheet = getOrCreateRelatoriosSheet(ss);
  ensureHeaders(sheet, RELATORIOS_HEADERS);
  const rows = sheet.getDataRange().getValues();
  const header = rows[0];
  const data = [];
  const escolasSheet = getEscolasSheet(ss);
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    const map = {};
    RELATORIOS_HEADERS.forEach((h, idx) => {
      map[h] = r[header.indexOf(h)];
    });
    // build output object
    const subjectsStr = normalizeListField(map['Motivos / Assuntos']);
    const techStr = normalizeListField(map['Técnicos Presentes']);
    const subjectsList = splitList(subjectsStr);
    const techniciansList = splitList(techStr);
    const fotosJsonStr = map['fotos_json'] ? String(map['fotos_json']) : '';
    const linkFotoStr = map['Link Foto'] ? String(map['Link Foto']) : '';
    const photos = parseFotosJsonForClient(fotosJsonStr, linkFotoStr);
    const municipio = resolveMunicipioFromReport(map, escolasSheet);
    data.push({
      id: map['ID do Relatório'] || '',
      creator: map['Usuário Logado'] || '',
      schoolName: map['Nome da Escola'] || '',
      visitDate: map['Data da Visita'] || '',
      isTechnicalAnalysis: map['Tipo de Relatório'] ? true : false,
      subjects: subjectsStr,
      motivos: subjectsStr,
      subjectsList: subjectsList,
      technicians: techStr,
      tecnicos: techStr,
      techniciansList: techniciansList,
      responsiblePerson: map['Responsável da Escola'] || '',
      observations: map['Observações'] || '',
      reportNumber: map['Número do Relatório'] || '',
      gre: map['Regional (GRE)'] || '',
      schoolAddress: map['Endereço da Escola'] || '',
      schoolCity: map['municipio'] || '',
      municipio: municipio,
      schoolInep: map['inep'] || '',
      inep: map['inep'] || '',
      signatureUrl: map['Link Assinatura'] || '',
      urlAssinatura: map['Link Assinatura'] || '',
      urlFotos: linkFotoStr,
      fotosJson: fotosJsonStr,
      fotos_json: fotosJsonStr,
      photos: photos,
      updatedAt: map['Data do Envio'] || ''
    });
  }
  return resposta({ status: 'success', success: true, data: data });
}

function saveReportAction(p) {
  const ss = getSpreadsheet();
  const relSheet = getOrCreateRelatoriosSheet(ss);
  ensureHeaders(relSheet, RELATORIOS_HEADERS);
  const header = relSheet.getRange(1, 1, 1, relSheet.getLastColumn()).getValues()[0];

  const lock = LockService.getDocumentLock();
  lock.waitLock(30000);
  try {
    const id = p.id || p.ID || p.id_relatorio || '';
    // Find existing row
    const data = relSheet.getDataRange().getValues();
    let rowIdx = -1;
    const idCol = header.indexOf('ID do Relatório');
    for (let i = 1; i < data.length; i++) {
      if (String(data[i][idCol]).trim() === String(id).trim()) {
        rowIdx = i + 1; // sheet rows are 1‑based
        break;
      }
    }
    // Prepare row values aligned with headers
    const rowVals = RELATORIOS_HEADERS.map(col => {
      const key = col.replace(/\s+/g, '').toLowerCase(); // simple mapping
      return p[key] !== undefined ? p[key] : '';
    });

    // Handle photo and signature uploads if base64 provided
    const driveFolder = DriveApp.getFoldersByName('AppSecretaria_Fotos').hasNext()
      ? DriveApp.getFoldersByName('AppSecretaria_Fotos').next()
      : DriveApp.createFolder('AppSecretaria_Fotos');
    // signature
    if (p.signatureBase64 || p.assinaturaBase64) {
      const sig = p.signatureBase64 || p.assinaturaBase64;
      const url = uploadBase64ToDrive(sig, driveFolder, 'signature_' + id + '.png');
      const idxSig = header.indexOf('Link Assinatura');
      if (idxSig >= 0) rowVals[idxSig] = url;
    }
    // photos array
    if (Array.isArray(p.fotosArray) && p.fotosArray.length) {
      const fotos = [];
      p.fotosArray.forEach((item, idx) => {
        const url = uploadBase64ToDrive(item.base64, driveFolder, 'photo_' + id + '_' + idx + '.png');
        fotos.push({ url: url, path: url, comment: item.comment || '' });
      });
      const jsonStr = JSON.stringify(fotos);
      const idxFotos = header.indexOf('fotos_json');
      if (idxFotos >= 0) rowVals[idxFotos] = jsonStr;
    }
    // Municipio resolution if missing
    const idxMun = header.indexOf('municipio');
    if (idxMun >= 0 && (!rowVals[idxMun] || rowVals[idxMun].toString().trim() === '')) {
      const escolasSheet = getEscolasSheet(ss);
      const mapTmp = {};
      RELATORIOS_HEADERS.forEach((c, i) => { mapTmp[c] = rowVals[i]; });
      rowVals[idxMun] = resolveMunicipioFromReport(mapTmp, escolasSheet);
    }

    if (rowIdx > 0) {
      // update existing
      relSheet.getRange(rowIdx, 1, 1, rowVals.length).setValues([rowVals]);
    } else {
      // append new row at bottom
      relSheet.appendRow(rowVals);
    }
    return resposta({ status: 'success', success: true, message: 'Report saved' });
  } finally {
    lock.releaseLock();
  }
}

function deleteReportAction(p) {
  const ss = getSpreadsheet();
  const relSheet = getOrCreateRelatoriosSheet(ss);
  const histSheet = getHistoricoSheet(ss);
  const header = relSheet.getRange(1, 1, 1, relSheet.getLastColumn()).getValues()[0];
  const id = p.id || '';
  const data = relSheet.getDataRange().getValues();
  const idCol = header.indexOf('ID do Relatório');
  let rowIdx = -1;
  for (let i = 1; i < data.length; i++) {
    if (String(data[i][idCol]).trim() === String(id).trim()) { rowIdx = i + 1; break; }
  }
  if (rowIdx === -1) {
    return resposta({ status: 'error', success: false, message: 'Report not found' });
  }
  // Archive to history
  const rowValues = relSheet.getRange(rowIdx, 1, 1, relSheet.getLastColumn()).getValues()[0];
  const histHeaders = ['DATA_SNAPSHOT', 'VERSAO', 'EDITADO_POR', 'DATA_REGISTRO', 'ID', 'USUARIO', 'ESCOLA', 'DATA_VISITA', 'TIPO', 'MOTIVOS', 'TECNICOS', 'RESPONSAVEL', 'OBSERVACOES', 'URL_ASSINATURA', 'URL_FOTOS', 'NUMERO_RELATORIO', 'GRE', 'ENDERECO', 'FOTOS_JSON', 'MUNICIPIO', 'INEP'];
  ensureHeaders(histSheet, histHeaders);
  const snap = new Date();
  const histRow = [];
  histHeaders.forEach(h => {
    switch (h) {
      case 'DATA_SNAPSHOT': histRow.push(snap); break;
      case 'VERSAO': histRow.push('1'); break; // simple version counter
      case 'EDITADO_POR': histRow.push(p.editedBy || ''); break;
      case 'DATA_REGISTRO': histRow.push(rowValues[header.indexOf('Data do Envio')] || ''); break;
      case 'ID': histRow.push(id); break;
      case 'USUARIO': histRow.push(rowValues[header.indexOf('Usuário Logado')] || ''); break;
      case 'ESCOLA': histRow.push(rowValues[header.indexOf('Nome da Escola')] || ''); break;
      case 'DATA_VISITA': histRow.push(rowValues[header.indexOf('Data da Visita')] || ''); break;
      case 'TIPO': histRow.push(rowValues[header.indexOf('Tipo de Relatório')] || ''); break;
      case 'MOTIVOS': histRow.push(rowValues[header.indexOf('Motivos / Assuntos')] || ''); break;
      case 'TECNICOS': histRow.push(rowValues[header.indexOf('Técnicos Presentes')] || ''); break;
      case 'RESPONSAVEL': histRow.push(rowValues[header.indexOf('Responsável da Escola')] || ''); break;
      case 'OBSERVACOES': histRow.push(rowValues[header.indexOf('Observações')] || ''); break;
      case 'URL_ASSINATURA': histRow.push(rowValues[header.indexOf('Link Assinatura')] || ''); break;
      case 'URL_FOTOS': histRow.push(rowValues[header.indexOf('Link Foto')] || ''); break;
      case 'NUMERO_RELATORIO': histRow.push(rowValues[header.indexOf('Número do Relatório')] || ''); break;
      case 'GRE': histRow.push(rowValues[header.indexOf('Regional (GRE)')] || ''); break;
      case 'ENDERECO': histRow.push(rowValues[header.indexOf('Endereço da Escola')] || ''); break;
      case 'FOTOS_JSON': histRow.push(rowValues[header.indexOf('fotos_json')] || ''); break;
      case 'MUNICIPIO': histRow.push(rowValues[header.indexOf('municipio')] || ''); break;
      case 'INEP': histRow.push(rowValues[header.indexOf('inep')] || ''); break;
      default: histRow.push('');
    }
  });
  histSheet.appendRow(histRow);
  // delete row
  relSheet.deleteRow(rowIdx);
  return resposta({ status: 'success', success: true, message: 'Report deleted' });
}

function fetchSchoolsAction(p) {
  const ss = getSpreadsheet();
  const sheet = getEscolasSheet(ss);
  if (!sheet) return resposta({ status: 'error', success: false, message: 'Escolas sheet not found' });
  const rows = sheet.getDataRange().getValues();
  const header = rows[0];
  const data = [];
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    data.push({
      id: r[header.indexOf('ID')] || '',
      inep: r[header.indexOf('INEP')] || '',
      nome: r[header.indexOf('NOME')] || '',
      endereco: r[header.indexOf('ENDERECO')] || '',
      municipio: r[header.indexOf('MUNICIPIO')] || '',
      uf: r[header.indexOf('UF')] || '',
      gre: r[header.indexOf('GRE')] || ''
    });
  }
  return resposta({ status: 'success', success: true, data: data });
}

function fetchTechniciansAction(p) {
  const ss = getSpreadsheet();
  const sheet = getTecnicosSheet(ss);
  if (!sheet) return resposta({ status: 'error', success: false, message: 'Tecnicos sheet not found' });
  const rows = sheet.getDataRange().getValues();
  const header = rows[0];
  const data = [];
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    data.push({
      id: r[header.indexOf('ID')] || '',
      nome: r[header.indexOf('NOME')] || '',
      matricula: r[header.indexOf('MATRICULA')] || '',
      email: r[header.indexOf('EMAIL')] || '',
      permissao: r[header.indexOf('PERMISSAO')] || '',
      senha: r[header.indexOf('SENHA')] || ''
    });
  }
  return resposta({ status: 'success', success: true, data: data });
}

function fetchHistoryAction(p) {
  const ss = getSpreadsheet();
  const sheet = getHistoricoSheet(ss);
  const rows = sheet.getDataRange().getValues();
  const header = rows[0];
  const data = [];
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    const obj = {};
    header.forEach((h, idx) => { obj[h] = r[idx]; });
    data.push(obj);
  }
  return resposta({ status: 'success', success: true, data: data });
}

function corrigirMunicipiosRelatoriosAction(p) {
  const ss = getSpreadsheet();
  const relSheet = getOrCreateRelatoriosSheet(ss);
  ensureHeaders(relSheet, RELATORIOS_HEADERS);
  const header = relSheet.getRange(1, 1, 1, relSheet.getLastColumn()).getValues()[0];
  const rows = relSheet.getDataRange().getValues();
  const escolasSheet = getEscolasSheet(ss);
  const idxMun = header.indexOf('municipio');
  const idxInep = header.indexOf('inep');
  const idxNomeEscola = header.indexOf('Nome da Escola');
  let updated = 0;
  for (let i = 1; i < rows.length; i++) {
    if (!rows[i][idxMun] || rows[i][idxMun].toString().trim() === '') {
      const mapTmp = {};
      RELATORIOS_HEADERS.forEach((c, idx) => { mapTmp[c] = rows[i][idx]; });
      const mun = resolveMunicipioFromReport(mapTmp, escolasSheet);
      if (mun) {
        relSheet.getRange(i + 1, idxMun + 1).setValue(mun);
        updated++;
      }
    }
  }
  return resposta({ status: 'success', success: true, message: 'Municipios corrected', updatedRows: updated });
}

function corrigirRelatoriosDuplicadosAction(p) {
  const dryRun = p.dryRun !== undefined ? Boolean(p.dryRun) : true;
  const ss = getSpreadsheet();
  const relSheet = getOrCreateRelatoriosSheet(ss);
  ensureHeaders(relSheet, RELATORIOS_HEADERS);
  const header = relSheet.getRange(1, 1, 1, relSheet.getLastColumn()).getValues()[0];
  const idCol = header.indexOf('ID do Relatório');
  const rows = relSheet.getDataRange().getValues();
  const map = {};
  const duplicates = [];
  for (let i = 1; i < rows.length; i++) {
    const id = String(rows[i][idCol] || '').trim();
    if (!id) continue;
    if (!map[id]) map[id] = [];
    map[id].push(i + 1); // sheet row number
  }
  for (const id in map) {
    if (map[id].length > 1) duplicates.push({ id, rows: map[id] });
  }
  let removed = 0;
  if (!dryRun) {
    // keep latest (max row number) and delete others
    duplicates.forEach(d => {
      const rowsToDelete = d.rows.slice(0, -1).sort((a, b) => b - a); // all but last, descending order
      rowsToDelete.forEach(rnum => {
        relSheet.deleteRow(rnum);
        removed++;
      });
    });
  }
  return resposta({
    status: 'success',
    success: true,
    dryRun: dryRun,
    duplicateCount: duplicates.length,
    removedRows: removed,
    details: duplicates
  });
}

// ---------- End of Script ----------
