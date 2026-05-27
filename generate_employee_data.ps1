# Script para gerar employee_data.dart a partir do XLSX extraído em temp_xlsx
$wsPath = ".\temp_xlsx\xl\worksheets\sheet1.xml"
$ssPath = ".\temp_xlsx\xl\sharedStrings.xml"
$outputPath = ".\lib\services\employee_data.dart"

Write-Host "Carregando shared strings..."
$ssXml = [xml](Get-Content $ssPath -Encoding UTF8)
$strings = $ssXml.sst.si | ForEach-Object { $_.t }
Write-Host "Total de strings: $($strings.Count)"

Write-Host "Carregando planilha..."
$wsXml = [xml](Get-Content $wsPath -Encoding UTF8)
$rows = $wsXml.worksheet.sheetData.row
Write-Host "Total de linhas: $($rows.Count)"

$employees = [System.Collections.Generic.List[PSCustomObject]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($row in $rows[1..($rows.Count - 1)]) {
    $cells = @{}
    foreach ($c in $row.c) {
        $col = $c.r -replace '[0-9]', ''
        $cells[$col] = $c
    }

    if ($cells['A'] -and $cells['B']) {
        $mat = $cells['A'].v
        if ($cells['B'].t -eq 's') {
            $nomeIdx = [int]$cells['B'].v
            $nome = $strings[$nomeIdx]
        } else {
            $nome = $cells['B'].v
        }

        if ($mat -and $nome -and $nome -ne 'NOME' -and $nome.Trim() -ne '') {
            $key = "$mat|$nome"
            if ($seen.Add($key)) {
                # Escapa aspas simples no nome (para Dart)
                $nomeEscaped = $nome -replace "'", "\\'" -replace '"', '\\"'
                $matStr = $mat.ToString().Trim()
                $employees.Add([PSCustomObject]@{ Matricula = $matStr; Nome = $nomeEscaped })
            }
        }
    }
}

Write-Host "Total de funcionários únicos: $($employees.Count)"
Write-Host "Gerando arquivo Dart..."

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("import '../models/employee_model.dart';")
$lines.Add("")
$lines.Add("final List<EmployeeModel> allEmployees = [")

foreach ($emp in $employees) {
    $lines.Add("  EmployeeModel(matricula: '$($emp.Matricula)', name: '$($emp.Nome)'),")
}

$lines.Add("];")

[System.IO.File]::WriteAllLines($outputPath, $lines, [System.Text.Encoding]::UTF8)

Write-Host "Arquivo gerado: $outputPath"
Write-Host "Tamanho: $([System.IO.FileInfo]::new($outputPath).Length / 1MB) MB"
