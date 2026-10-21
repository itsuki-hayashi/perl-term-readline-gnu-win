/* SPDX-FileCopyrightText: 2026 Itsuki Hayashi
 * SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef _MSC_VER
#error Visual C++ is required
#endif
GNUWIN32_MSC_VER _MSC_VER
#if defined(_M_ARM64)
GNUWIN32_MSC_ARCH arm64
#elif defined(_M_X64)
GNUWIN32_MSC_ARCH amd64
#else
#error Only native x64 and ARM64 targets are supported
#endif
