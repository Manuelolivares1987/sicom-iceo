'use client'

import Link from 'next/link'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'

export type QuickAction = {
  label: string
  description?: string
  href: string
  icon: React.ComponentType<{ className?: string }>
  accent?: 'green' | 'amber' | 'blue' | 'red' | 'slate' | 'purple'
  badge?: string
}

const ACCENT: Record<NonNullable<QuickAction['accent']>, { ring: string; bg: string; text: string; iconBg: string }> = {
  green:  { ring: 'hover:ring-emerald-300', bg: 'hover:bg-emerald-50',  text: 'text-emerald-700',  iconBg: 'bg-emerald-100' },
  amber:  { ring: 'hover:ring-amber-300',   bg: 'hover:bg-amber-50',    text: 'text-amber-700',    iconBg: 'bg-amber-100' },
  blue:   { ring: 'hover:ring-sky-300',     bg: 'hover:bg-sky-50',      text: 'text-sky-700',      iconBg: 'bg-sky-100' },
  red:    { ring: 'hover:ring-red-300',     bg: 'hover:bg-red-50',      text: 'text-red-700',      iconBg: 'bg-red-100' },
  slate:  { ring: 'hover:ring-slate-300',   bg: 'hover:bg-slate-50',    text: 'text-slate-700',    iconBg: 'bg-slate-100' },
  purple: { ring: 'hover:ring-purple-300',  bg: 'hover:bg-purple-50',   text: 'text-purple-700',   iconBg: 'bg-purple-100' },
}

export function QuickActionsGrid({
  title,
  actions,
  cols = 4,
}: {
  title?: string
  actions: QuickAction[]
  cols?: 2 | 3 | 4 | 5 | 6
}) {
  const colClass = {
    2: 'sm:grid-cols-2',
    3: 'sm:grid-cols-2 lg:grid-cols-3',
    4: 'sm:grid-cols-2 lg:grid-cols-4',
    5: 'sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5',
    6: 'sm:grid-cols-3 lg:grid-cols-6',
  }[cols]

  return (
    <section>
      {title && (
        <h2 className="text-xs uppercase tracking-wide text-gray-500 mb-2 font-medium">{title}</h2>
      )}
      <div className={cn('grid grid-cols-1 gap-2', colClass)}>
        {actions.map((a) => {
          const Icon = a.icon
          const tone = ACCENT[a.accent ?? 'slate']
          return (
            <Link
              key={a.href + a.label}
              href={a.href}
              className={cn(
                'group flex items-center gap-3 rounded-lg border border-gray-200 bg-white p-3',
                'transition-all hover:shadow-sm hover:ring-2',
                tone.ring,
                tone.bg,
              )}
            >
              <div className={cn('rounded-lg p-2 flex-shrink-0', tone.iconBg)}>
                <Icon className={cn('h-5 w-5', tone.text)} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1">
                  <span className="text-sm font-medium text-gray-900 truncate">{a.label}</span>
                  {a.badge && (
                    <span className="rounded-full bg-gray-100 px-1.5 py-0.5 text-[9px] uppercase text-gray-600">
                      {a.badge}
                    </span>
                  )}
                </div>
                {a.description && (
                  <div className="text-[11px] text-gray-500 truncate">{a.description}</div>
                )}
              </div>
              <ChevronRight className={cn('h-4 w-4 text-gray-300 transition-colors group-hover:text-gray-500')} />
            </Link>
          )
        })}
      </div>
    </section>
  )
}
