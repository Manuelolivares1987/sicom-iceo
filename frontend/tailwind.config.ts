import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // Pillado Empresas - Colores corporativos
        pillado: {
          green: {
            50: '#f0f9f1',
            100: '#dbf0de',
            200: '#b9e1bf',
            300: '#8bcc95',
            400: '#5bb268',
            500: '#2D8B3D',
            600: '#257032',
            700: '#1e5929',
            800: '#1a4723',
            900: '#163b1e',
          },
          orange: {
            50: '#fef6ee',
            100: '#fdebd7',
            200: '#fad3ae',
            300: '#f6b47b',
            400: '#f19245',
            500: '#E87722',
            600: '#d45e14',
            700: '#b04613',
            800: '#8d3917',
            900: '#733116',
          },
        },
        // Semáforos operacionales
        semaforo: {
          rojo: '#DC2626',
          amarillo: '#F59E0B',
          verde: '#16A34A',
          azul: '#2563EB',
        },
        // ICEO clasificación
        iceo: {
          deficiente: '#DC2626',
          aceptable: '#F59E0B',
          bueno: '#16A34A',
          excelencia: '#7C3AED',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
    },
  },
  plugins: [],
}

export default config
