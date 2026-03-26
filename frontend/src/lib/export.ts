// Export data as CSV and trigger download
export function exportToCSV(data: Record<string, any>[], filename: string, columns: { key: string, label: string }[]) {
  const header = columns.map(c => c.label).join(',')
  const rows = data.map(row =>
    columns.map(c => {
      const val = row[c.key]
      // Escape commas and quotes in CSV
      const str = String(val ?? '')
      return str.includes(',') || str.includes('"') ? `"${str.replace(/"/g, '""')}"` : str
    }).join(',')
  )
  const csv = [header, ...rows].join('\n')
  const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${filename}.csv`
  link.click()
  URL.revokeObjectURL(url)
}

// Export data as Excel-compatible HTML table and trigger download
export function exportToExcel(data: Record<string, any>[], filename: string, columns: { key: string, label: string }[], sheetName?: string) {
  const headerRow = columns.map(c => `<th style="background:#2D8B3D;color:white;padding:8px;border:1px solid #ccc">${c.label}</th>`).join('')
  const dataRows = data.map(row =>
    columns.map(c => `<td style="padding:6px;border:1px solid #eee">${row[c.key] ?? ''}</td>`).join('')
  ).map(r => `<tr>${r}</tr>`).join('')

  const html = `
    <html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel">
    <head><meta charset="UTF-8"></head>
    <body>
      <table>
        <thead><tr>${headerRow}</tr></thead>
        <tbody>${dataRows}</tbody>
      </table>
    </body></html>`

  const blob = new Blob([html], { type: 'application/vnd.ms-excel;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `${filename}.xls`
  link.click()
  URL.revokeObjectURL(url)
}
