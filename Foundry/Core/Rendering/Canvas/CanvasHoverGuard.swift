import Foundation

/// Canvas-only CSS gating: WebKit can retain its last :hover match after a native exit.
nonisolated enum CanvasHoverGuard {
    static let javaScript = #"""
    (() => {
      const attribute = 'data-foundry-pointer-outside';
      const directHoverAttribute = 'data-foundry-direct-hover';
      const guard = ':where(:not(:root[' + attribute + '], :root[' + attribute + '] *))';
      const customTrigger = /(:has\(\s*#([A-Za-z][A-Za-z0-9_-]*)):hover\b/gi;
      const protectedCustomTrigger = new RegExp(
        ':has\\(\\s*#([A-Za-z][A-Za-z0-9_-]*)\\[' + directHoverAttribute + '\\]',
        'gi'
      );
      let customTriggerIDs = new Set();
      const protectRules = rules => {
        for (const rule of rules) {
          if (typeof rule.selectorText === 'string' && !rule.selectorText.includes(guard)) {
            let selector = rule.selectorText.replace(customTrigger, (_, prefix, id) => {
              customTriggerIDs.add(id);
              return prefix + '[' + directHoverAttribute + ']';
            });
            for (const match of selector.matchAll(protectedCustomTrigger)) customTriggerIDs.add(match[1]);
            // Leave quoted attribute values and escaped characters alone.
            selector = selector.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\\.|:hover\b/gi,
              token => token.toLowerCase() === ':hover' ? token + guard : token);
            if (selector !== rule.selectorText) rule.selectorText = selector;
          } else if (typeof rule.selectorText === 'string') {
            for (const match of rule.selectorText.matchAll(protectedCustomTrigger)) customTriggerIDs.add(match[1]);
          }
          if (rule.cssRules) protectRules(rule.cssRules);
        }
      };
      const protectStyles = () => {
        customTriggerIDs = new Set();
        for (const sheet of document.styleSheets) {
          // Cross-origin stylesheets do not expose CSSOM rules.
          try { protectRules(sheet.cssRules); } catch (_) {}
        }
      };
      window.foundrySetCanvasPointerInside = inside => {
        document.documentElement.toggleAttribute(attribute, !inside);
        if (!inside) {
          document.querySelectorAll('[' + directHoverAttribute + ']')
            .forEach(element => element.removeAttribute(directHoverAttribute));
        }
      };
      window.foundryUpdateCanvasPointer = (x, y) => {
        window.foundrySetCanvasPointerInside(true);
        for (const id of customTriggerIDs) {
          const element = document.getElementById(id);
          if (!element) continue;
          const rect = element.getBoundingClientRect();
          const containsPointer = x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom;
          element.toggleAttribute(directHoverAttribute, containsPointer);
        }
      };
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
