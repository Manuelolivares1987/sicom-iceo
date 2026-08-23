import { register } from 'node:module'
import { pathToFileURL } from 'node:url'
register('./_resolver.mjs', pathToFileURL(import.meta.filename))
