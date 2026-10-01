import Foundation

/// Canvas-only CSS gating: WebKit can retain its last :hover match after a native exit.
nonisolated enum CanvasHoverGuard {
    static let javaScript = #"""
    (() => {
      const attribute = 'data-foundry-pointer-outside';
      const guard = ':where(:not(:root[' + attribute + '], :root[' + attribute + '] *))';
      const protectRules = rules => {
        for (const rule of rules) {
          if (typeof rule.selectorText === 'string' && !rule.selectorText.includes(guard)) {
            // Leave quoted attribute values and escaped characters alone.
            const selector = rule.selectorText.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\\.|:hover\b/gi,
              token => token.toLowerCase() === ':hover' ? token + guard : token);
            if (selector !== rule.selectorText) rule.selectorText = selector;
          }
          if (rule.cssRules) protectRules(rule.cssRules);
        }
      };
      const protectStyles = () => {
        for (const sheet of document.styleSheets) {
          // Cross-origin stylesheets do not expose CSSOM rules.
          try { protectRules(sheet.cssRules); } catch (_) {}
        }
      };
      window.foundrySetCanvasPointerInside = inside => {
        document.documentElement.toggleAttribute(attribute, !inside);
      };
      document.addEventListener('pointermove', () => window.foundrySetCanvasPointerInside(true), true);
      protectStyles();
      new MutationObserver(records => {
        if (records.some(record => record.target.nodeName === 'STYLE'
            || record.target.parentElement?.nodeName === 'STYLE'
            || [...record.addedNodes].some(node => node.nodeType === 1
              && (node.matches('style,link[rel="stylesheet"]') || node.querySelector('style,link[rel="stylesheet"]'))))) {
          protectStyles();
        }
      }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
      document.addEventListener('load', event => {
        if (event.target.matches?.('link[rel="stylesheet"]')) protectStyles();
      }, true);
    })();
    """#
}
