export const NextResponse = { json: (b: unknown, i?: { status?: number }) => new Response(JSON.stringify(b), { status: i?.status ?? 200, headers: { 'content-type': 'application/json' } }) }
