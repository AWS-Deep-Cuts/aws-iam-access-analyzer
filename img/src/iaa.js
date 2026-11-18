// IAM Access Analyzer の回の図の補助。wires.js の後に読み込む。
// path([[x, y], [x, y], ...], {hot, dash, noarrow}) … 座標で水平・垂直の折れ線を引く（#fig の左上が 0）
(function () {
  const NS = 'http://www.w3.org/2000/svg';
  window.path = function (pts, o = {}) {
    const svg = document.getElementById('wires');
    const p = document.createElementNS(NS, 'polyline');
    p.setAttribute('points', pts.map((q) => q.join(',')).join(' '));
    p.setAttribute('fill', 'none');
    p.setAttribute('stroke', o.hot ? '#ff4d00' : (o.color || '#0c0c0c'));
    p.setAttribute('stroke-width', o.width || '2.5');
    if (o.dash) p.setAttribute('stroke-dasharray', '6 5');
    if (!o.noarrow) p.setAttribute('marker-end', o.hot ? 'url(#ah)' : 'url(#ak)');
    svg.appendChild(p);
  };
})();
