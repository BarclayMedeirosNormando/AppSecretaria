$objExcel = New-Object -ComObject Excel.Application
$objExcel.Visible = $false
$workbook = $objExcel.Workbooks.Open("C:\Users\barclaym\Downloads\Nexus Educacional.xlsx")
$worksheet = $workbook.Sheets.Item("ESCOLAS")
$row = 2
$out = "import '../models/school_model.dart';`n`nfinal List<SchoolModel> initialSchools = ["

while ($true) {
    $inep = $worksheet.Cells.Item($row, 1).Text
    if ([string]::IsNullOrWhiteSpace($inep)) { break }
    
    $name = $worksheet.Cells.Item($row, 2).Text
    $gre = $worksheet.Cells.Item($row, 3).Text
    $address = $worksheet.Cells.Item($row, 4).Text
    $city = $worksheet.Cells.Item($row, 6).Text
    $uf = $worksheet.Cells.Item($row, 7).Text
    
    $name = $name -replace "'", "\'"
    $address = $address -replace "'", "\'"
    $city = $city -replace "'", "\'"
    $gre = $gre -replace "'", "\'"
    $inep = $inep -replace "'", "\'"

    $id = [Guid]::NewGuid().ToString()

    $out += "`n  SchoolModel(id: '$id', inep: '$inep', name: '$name', address: '$address', city: '$city', uf: '$uf', gre: '$gre'),"
    $row++
}
$out += "`n];"

Set-Content -Path "C:\Users\barclaym\Documents\AppSecretaria\lib\services\school_data.dart" -Value $out -Encoding UTF8
$workbook.Close($false)
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($worksheet) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbook) | Out-Null
[System.Runtime.Interopservices.Marshal]::ReleaseComObject($objExcel) | Out-Null
$objExcel.Quit()
