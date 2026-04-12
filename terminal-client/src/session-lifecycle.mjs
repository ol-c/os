const defaultCloseFallbackDelayMs = 250;

export function createSessionLifecycle({
  windowRef,
  terminalNode = null,
  closeFallbackDelayMs = defaultCloseFallbackDelayMs,
  onCloseBlocked = () => {},
} = {}) {
  if (!windowRef) {
    throw new Error('createSessionLifecycle requires a windowRef');
  }

  let closeAttempted = false;

  function closeRootSessionTab() {
    if (closeAttempted) {
      return;
    }
    closeAttempted = true;

    if (terminalNode) {
      terminalNode.dataset.rootSessionExited = 'true';
    }

    windowRef.close();
    windowRef.setTimeout(() => {
      if (!windowRef.closed) {
        onCloseBlocked();
      }
    }, closeFallbackDelayMs);
  }

  return {
    closeRootSessionTab,
  };
}
