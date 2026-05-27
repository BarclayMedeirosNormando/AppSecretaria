// Apps Script for Nexus Relatórios - Clean and Unified Implementation
// ------------------------------------------------------------
// This script provides a single source of truth for all backend actions
// required by the Flutter app. It avoids duplicated functions, ensures
// consistent field handling, and normalizes data to prevent runtime
// type errors in the client (e.g., List<String> vs. String).
// ------------------------------------------------------------

// ==== Configuration ==== //
const SHEET_RELATORIOS = 'RELATORIOS';
const SHEET_HISTORICO = 'historico_relatorios'; // exact name as requested
const SHEET_AUDITORIA = 'auditoria_relatorios';
const SHEET_CONFIG = 'Configuracoes';
const SHEET_ESCOLAS = 'EScolas';
const SHEET_TECNICOS = 'Tecnicos';

// Mapping of possible header aliases to canonical field names
const RELATORIO_FIELD_ALIASES = {
  // Primary fields
  'id': 'id',
  'numeroRelatorio': 'numeroRelatorio',
  // Strings that may appear in different variants
  'subjects': 'subjects',
  'subjectsList': 'subjectsList',
  'motivos': 'subjects', // alias for subjects
  'technicians': 'technicians',
  'techniciansList': 'techniciansList',
  'tecnicos': 'technicians', // alias for technicians
  // Photos / URLs
  'urlFotos': 'urlFotos',
  'photos': 'photos',
  'fotos_json': 'fotosJson',
  'fotosJson': 'fotosJson',
  'fotosJson': 'fotosJson',
  'fotosJson': 'fotosJson',
  // Legacy aliases (kept for backward compatibility)
  'fotos_json': 'fotosJson',
  'Link Foto': 'urlFotos',
  'photos_json': 'fotosJson',
  // Miscellaneous
  'municipio': 'municipio',
  'inep': 'inep',
  'versao': 'versao',
  'editadoPor': 'editadoPor',
  // ... add other common fields as needed
};

/** Utility: Get a sheet by name, create if missing (for required sheets). */
function getOrCreateSheet(name, headers = []) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    if (headers.length) {
      sheet.appendRow(headers);
    }
  }
  return sheet;
}

/** Helper: Normalise header row to canonical field names. */
function normalizeHeaders(row) {
  return row.map(h => {
    const lower = (h || '').toString().toLowerCase().trim();
    return RELATORIO_FIELD_ALIASES[lower] || lower;
  });
}

/** Helper: Convert a value to a safe string. */
function asString(value) {
  if (value === null || value === undefined) return '';
  if (Array.isArray(value)) return JSON.stringify(value);
  if (typeof value === 'object') return JSON.stringify(value);
  return value.toString();
}

/** Helper: Convert a value to a safe string list (array). */
function asStringList(value) {
  if (!value) return [];
  if (Array.isArray(value)) return value.map(v => v.toString());
  // If the value is a comma/semicolon separated string, split it
  const str = value.toString();
  return str.split(/[;,\n]/).map(s => s.trim()).filter(s => s);
}

/** Helper: Ensure a map (object) is safely returned. */
function asMap(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  return {};
}

/** Respond with JSON and proper CORS headers. */
function jsonResponse(data, code = 200) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON)
    .setHeader('Access-Control-Allow-Origin', '*')
    .setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
    .setHeader('Access-Control-Allow-Headers', 'Content-Type')
    .setResponseCode(code);
}

/** Entry point for POST requests from the Flutter app. */
function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const action = payload.action;
    switch (action) {
      case 'login':
        return loginAction(payload);
      case 'checkVersion':
        return checkVersionAction();
      case 'fetchReports':
        return fetchReportsAction(payload);
      case 'sendReport':
        return sendReportAction(payload);
      case 'updateReport':
        return updateReportAction(payload);
      case 'deleteReport':
        return deleteReportAction(payload);
      case 'fetchSchools':
        return fetchSchoolsAction();
      case 'saveSchool':
        return saveSchoolAction(payload);
      case 'deleteSchool':
        return deleteSchoolAction(payload);
      case 'fetchTechnicians':
        return fetchTechniciansAction();
      case 'saveTechnician':
        return saveTechnicianAction(payload);
      case 'deleteTechnician':
        return deleteTechnicianAction(payload);
      case 'fetchHistory':
        return fetchHistoryAction(payload);
      case 'fetchEmployees':
        return fetchEmployeesAction();
      case 'corrigirMunicipiosRelatorios':
        return corrigirMunicipiosRelatoriosAction();
      case 'corrigirRelatoriosDuplicados':
        return corrigirRelatoriosDuplicadosAction(payload);
      case 'syncReportsBatch':
        return syncReportsBatchAction(payload);
      default:
        return jsonResponse({error: 'Ação desconhecida: ' + action}, 400);
    }
  } catch (err) {
    return jsonResponse({error: err.message, stack: err.stack}, 500);
  }
}

/** Simple GET entry point (used for health check). */
function doGet(e) {
  return jsonResponse({status: 'online', timestamp: new Date().toISOString()});
}

/** ---------- Actions ---------- */

function loginAction(payload) {
  const {username, password} = payload;
  const sheet = getOrCreateSheet('Usuarios', ['username', 'password', 'role']);
  const data = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(data[0]);
  const rows = data.slice(1);
  for (const row of rows) {
    const record = {};
    headers.forEach((h, i) => record[h] = row[i]);
    if (record.username === username && record.password === password) {
      return jsonResponse({success: true, role: record.role || 'user'});
    }
  }
  return jsonResponse({success: false, error: 'Credenciais inválidas'}, 401);
}

function checkVersionAction() {
  const sheet = getOrCreateSheet(SHEET_CONFIG, [
    'VERSAO_ATUAL', 'LINK_DOWNLOAD', 'VERSAO_ANDROID', 'LINK_ANDROID', 'VERSAO_WINDOWS', 'LINK_WINDOWS'
  ]);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) {
    return jsonResponse({error: 'Config sheet empty'}, 500);
  }
  const headers = normalizeHeaders(data[0]);
  const values = {};
  headers.forEach((h, i) => values[h] = data[1][i]);
  return jsonResponse({config: values});
}

/** Fetch reports from RELATORIOS sheet. */
function fetchReportsAction(payload) {
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({reports: []});
  const headers = normalizeHeaders(data[0]);
  const reports = data.slice(1).map(row => {
    const rec = {};
    headers.forEach((h, i) => {
      const raw = row[i];
      // Normalize fields that must be strings for the client
      if (['subjects', 'technicians', 'motivos', 'tecnicos', 'urlFotos', 'fotosJson', 'fotos_json'].includes(h)) {
        rec[h] = asString(raw);
      } else if (h === 'photos') {
        // Expect array; if string, try to parse JSON, otherwise empty array
        if (Array.isArray(raw)) {
          rec[h] = raw;
        } else if (typeof raw === 'string' && raw.trim()) {
          try { rec[h] = JSON.parse(raw); } catch (_) { rec[h] = []; }
        } else {
          rec[h] = [];
        }
      } else {
        rec[h] = raw;
      }
    });
    // Provide list versions for convenience
    rec.subjectsList = asStringList(rec.subjects);
    rec.techniciansList = asStringList(rec.technicians);
    return rec;
  });
  return jsonResponse({reports});
}

/** Save a new report to RELATORIOS. */
function sendReportAction(payload) {
  const report = payload.report || {};
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const headers = sheet.getDataRange().offset(0, 0, 1).getValues()[0];
  const normHeaders = normalizeHeaders(headers);
  const row = normHeaders.map(h => report[h] !== undefined ? report[h] : '');
  sheet.appendRow(row);
  return jsonResponse({success: true, id: row[0]});
}

/** Update an existing report (matched by id). */
function updateReportAction(payload) {
  const {id, updates} = payload;
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const data = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(data[0]);
  for (let r = 1; r < data.length; r++) {
    const row = data[r];
    const idx = headers.indexOf('id');
    if (idx >= 0 && row[idx] == id) {
      const newRow = row.slice();
      for (const key in updates) {
        const col = headers.indexOf(key);
        if (col >= 0) newRow[col] = updates[key];
      }
      sheet.getRange(r + 1, 1, 1, newRow.length).setValues([newRow]);
      return jsonResponse({success: true});
    }
  }
  return jsonResponse({error: 'Report not found'}, 404);
}

/** Delete a report by id. */
function deleteReportAction(payload) {
  const {id} = payload;
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const data = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(data[0]);
  const idCol = headers.indexOf('id');
  for (let r = 1; r < data.length; r++) {
    if (data[r][idCol] == id) {
      sheet.deleteRow(r + 1);
      return jsonResponse({success: true});
    }
  }
  return jsonResponse({error: 'Report not found'}, 404);
}

/** Fetch schools from EScolas sheet. */
function fetchSchoolsAction() {
  const sheet = getOrCreateSheet(SHEET_ESCOLAS, ['nome', 'codigo', 'endereco']);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({schools: []});
  const headers = normalizeHeaders(data[0]);
  const schools = data.slice(1).map(row => {
    const obj = {};
    headers.forEach((h, i) => obj[h] = row[i]);
    return obj;
  });
  return jsonResponse({schools});
}

function saveSchoolAction(payload) {
  const school = payload.school || {};
  const sheet = getOrCreateSheet(SHEET_ESCOLAS);
  const headers = normalizeHeaders(sheet.getDataRange().offset(0,0,1).getValues()[0]);
  const row = headers.map(h => school[h] ?? '');
  sheet.appendRow(row);
  return jsonResponse({success: true});
}

function deleteSchoolAction(payload) {
  const {codigo} = payload;
  const sheet = getOrCreateSheet(SHEET_ESCOLAS);
  const data = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(data[0]);
  const codeCol = headers.indexOf('codigo');
  for (let r = 1; r < data.length; r++) {
    if (data[r][codeCol] == codigo) { sheet.deleteRow(r+1); return jsonResponse({success:true}); }
  }
  return jsonResponse({error:'School not found'},404);
}

/** Fetch technicians. */
function fetchTechniciansAction() {
  const sheet = getOrCreateSheet(SHEET_TECNICOS, ['nome', 'registro', 'categoria']);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({technicians: []});
  const headers = normalizeHeaders(data[0]);
  const techs = data.slice(1).map(row => {
    const obj = {};
    headers.forEach((h,i)=>obj[h]=row[i]);
    return obj;
  });
  return jsonResponse({technicians: techs});
}

function saveTechnicianAction(payload) {
  const tech = payload.technician || {};
  const sheet = getOrCreateSheet(SHEET_TECNICOS);
  const headers = normalizeHeaders(sheet.getDataRange().offset(0,0,1).getValues()[0]);
  const row = headers.map(h => tech[h] ?? '');
  sheet.appendRow(row);
  return jsonResponse({success:true});
}

function deleteTechnicianAction(payload) {
  const {registro} = payload;
  const sheet = getOrCreateSheet(SHEET_TECNICOS);
  const data = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(data[0]);
  const regCol = headers.indexOf('registro');
  for (let r=1; r<data.length; r++) {
    if (data[r][regCol] == registro) { sheet.deleteRow(r+1); return jsonResponse({success:true}); }
  }
  return jsonResponse({error:'Technician not found'},404);
}

/** Fetch historical reports from historico_relatorios sheet. */
function fetchHistoryAction(payload) {
  const sheet = getOrCreateSheet(SHEET_HISTORICO);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({history: []});
  const headers = normalizeHeaders(data[0]);
  const history = data.slice(1).map(row => {
    const rec = {};
    headers.forEach((h,i)=>{
      const raw = row[i];
      if (['subjects','technicians','motivos','tecnicos','urlFotos','fotosJson','fotos_json'].includes(h)) {
        rec[h] = asString(raw);
      } else if (h==='photos') {
        if (Array.isArray(raw)) rec[h]=raw;
        else if (typeof raw==='string' && raw.trim()) { try {rec[h]=JSON.parse(raw);} catch(e){rec[h]=[]} }
        else rec[h]=[];
      } else {
        rec[h]=raw;
      }
    });
    rec.subjectsList = asStringList(rec.subjects);
    rec.techniciansList = asStringList(rec.technicians);
    return rec;
  });
  return jsonResponse({history});
}

/** Fetch employees (funcionarios) – placeholder, implement as needed. */
function fetchEmployeesAction() {
  // Assuming a sheet named 'Funcionarios' exists
  const sheet = getOrCreateSheet('Funcionarios');
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({employees: []});
  const headers = normalizeHeaders(data[0]);
  const employees = data.slice(1).map(row=>{
    const obj={};
    headers.forEach((h,i)=>obj[h]=row[i]);
    return obj;
  });
  return jsonResponse({employees});
}

/** Corrigir municípios nos relatórios – simple pass‑through for now. */
function corrigirMunicipiosRelatoriosAction() {
  // Implement logic if needed; currently a no‑op.
  return jsonResponse({success:true, message:'Municipios corrigidos (noop)'});
}

/** Remove duplicated reports. payload.dryRun defaults to true. */
function corrigirRelatoriosDuplicadosAction(payload) {
  const dryRun = payload && payload.dryRun !== undefined ? payload.dryRun : true;
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return jsonResponse({removed:0, dryRun});
  const headers = normalizeHeaders(data[0]);
  const idCol = headers.indexOf('id');
  const seen = {};
  const rowsToDelete = [];
  for (let r=1; r<data.length; r++) {
    const id = data[r][idCol];
    if (seen[id]) rowsToDelete.push(r+1);
    else seen[id]=true;
  }
  // Delete from bottom to top to keep indices stable
  if (!dryRun) {
    for (let i=rowsToDelete.length-1; i>=0; i--) {
      sheet.deleteRow(rowsToDelete[i]);
    }
  }
  return jsonResponse({removed: rowsToDelete.length, dryRun});
}

/** Batch sync reports – optional implementation. */
function syncReportsBatchAction(payload) {
  // Expected payload: {reports: [{...}, ...]}
  const reports = payload.reports || [];
  const sheet = getOrCreateSheet(SHEET_RELATORIOS);
  const existing = sheet.getDataRange().getValues();
  const headers = normalizeHeaders(existing[0] || []);
  const idCol = headers.indexOf('id');
  const updates = [];
  const inserts = [];
  const idMap = {};
  // Build map of existing ids
  for (let r=1; r<existing.length; r++) {
    const id = existing[r][idCol];
    if (id) idMap[id] = r+1; // row number
  }
  reports.forEach(rep=>{
    const rowVals = headers.map(h=> rep[h] ?? '');
    if (rep.id && idMap[rep.id]) {
      updates.push({row:idMap[rep.id], values:rowVals});
    } else {
      inserts.push(rowVals);
    }
  });
  // Apply updates
  updates.forEach(u=>{
    sheet.getRange(u.row,1,1,u.values.length).setValues([u.values]);
  });
  // Append inserts
  if (inserts.length) {
    sheet.getRange(sheet.getLastRow()+1,1,inserts.length,inserts[0].length).setValues(inserts);
  }
  return jsonResponse({updated:updates.length, inserted:inserts.length});
}

/** ---- End of script ---- */

// Note: All field normalisation is performed here to guarantee that the Flutter
// client always receives strings for the listed fields, eliminating the runtime
// cast error (List<String> vs. String). The script automatically creates missing
// sheets with appropriate headers, providing a clean deployment experience.
