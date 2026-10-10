// Runs before first paint (and as an external file, because the CSP forbids inline scripts) so a saved theme never flashes.
try { var t = localStorage.getItem('theme'); if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t } catch (e) {}
