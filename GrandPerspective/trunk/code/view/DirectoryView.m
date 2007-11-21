#import "DirectoryView.h"

#import "math.h"

#import "FileItem.h"

#import "TreeLayoutBuilder.h"
#import "ItemTreeDrawer.h"
#import "ItemTreeDrawerSettings.h"
#import "ItemPathDrawer.h"
#import "ItemPathBuilder.h"
#import "ItemPathModel.h"

#import "TreeLayoutTraverser.h"

#import "AsynchronousTaskManager.h"
#import "DrawTaskExecutor.h"
#import "DrawTaskInput.h"


@interface DirectoryView (PrivateMethods)

// Called as part of "postInit"
- (void) setItemPathModel:(ItemPathModel*)pathModelVal;

- (void) forceRedraw;

- (void) itemTreeImageReady: (id) image;

- (void) selectedItemChanged: (NSNotification *)notification;
- (void) visibleItemTreeChanged: (NSNotification *)notification;
- (void) visibleItemPathLockingChanged: (NSNotification *)notification;
- (void) windowMainStatusChanged: (NSNotification *) notification;

- (void) buildPathToMouseLoc: (NSPoint) point;

@end  


@implementation DirectoryView

- (id) initWithFrame:(NSRect)frame {
  if (self = [super initWithFrame:frame]) {
    layoutBuilder = [[TreeLayoutBuilder alloc] init];

    DrawTaskExecutor  *drawTaskExecutor = [[DrawTaskExecutor alloc] init];  
    drawTaskManager = 
      [[AsynchronousTaskManager alloc] initWithTaskExecutor: drawTaskExecutor];
    [drawTaskExecutor release];

    pathDrawer = [[ItemPathDrawer alloc] init];
  }

  return self;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  [drawTaskManager dispose];
  [drawTaskManager release];

  [layoutBuilder release];

  [pathDrawer release];
  [pathBuilder release];
  [pathModel release];
  
  [treeImage release];
  
  [super dealloc];
}


- (void) postInitWithItemPathModel: (ItemPathModel *)pathModelVal {
  [self setItemPathModel: pathModelVal];
}


- (ItemPathModel *) itemPathModel {
  return pathModel;
}


- (BOOL) showEntireVolume {
  return showEntireVolume;
}

- (void) setShowEntireVolume: (BOOL) showEntireVolumeVal {
  if (showEntireVolume != showEntireVolumeVal) {
    showEntireVolume = showEntireVolumeVal;
    [self forceRedraw];
  }
}


- (ItemTreeDrawerSettings *) treeDrawerSettings {
  DrawTaskExecutor  *drawTaskExecutor = 
    (DrawTaskExecutor*)[drawTaskManager taskExecutor];

  return [drawTaskExecutor treeDrawerSettings];
}

- (void) setTreeDrawerSettings: (ItemTreeDrawerSettings *)settings {
  DrawTaskExecutor  *drawTaskExecutor = 
    (DrawTaskExecutor*)[drawTaskManager taskExecutor];

  if (settings != [drawTaskExecutor treeDrawerSettings]) {
    [drawTaskExecutor setTreeDrawerSettings: settings];
    [self forceRedraw];
  }
}


- (TreeLayoutBuilder*) layoutBuilder {
  return layoutBuilder;
}


- (void) drawRect:(NSRect)rect {
  if (pathModel==nil) {
    return;
  }

  if (treeImage==nil || !NSEqualSizes([treeImage size], [self bounds].size)) {
    NSAssert([self bounds].origin.x == 0 &&
             [self bounds].origin.y == 0, @"Bounds not at (0, 0)");

    [[NSColor blackColor] set];
    NSRectFill([self bounds]);
    
    // Create image in background thread.
    DrawTaskInput  *drawInput = 
      [[DrawTaskInput alloc] initWithItemSubTree: [pathModel visibleItemTree] 
                               layoutBuilder: layoutBuilder
                               bounds: [self bounds]];
    [drawTaskManager asynchronouslyRunTaskWithInput: drawInput callback: self 
                       selector: @selector(itemTreeImageReady:)];
    [drawInput release];
  }
  else {
    [treeImage compositeToPoint:NSZeroPoint operation:NSCompositeCopy];
  
    [pathDrawer drawItemPath: [pathModel itemPathToSelectedFileItem] 
                  tree: [pathModel visibleItemTree] 
                  usingLayoutBuilder: layoutBuilder
                  bounds: [self bounds]];
  }
}


- (BOOL) acceptsFirstResponder {
  return YES;
}

- (BOOL) becomeFirstResponder {
  return YES;
}

- (BOOL) resignFirstResponder {
  return YES;
}


- (void) keyDown: (NSEvent *)theEvent {
  NSString*  chars = [theEvent characters];
  if ([chars isEqualToString: @"]"]) {
    if ([pathModel canMoveSelectionDown]) {
      [pathModel moveSelectionDown];
      
      // Automatically lock path
      [pathModel setVisibleItemPathLocking: YES];
    }
  }
  else if ([chars isEqualToString: @"["]) {
    if ([pathModel canMoveSelectionUp]) {
      [pathModel moveSelectionUp];
      
      // Automatically lock path
      [pathModel setVisibleItemPathLocking: YES];
    }
  }
}


- (void) mouseDown: (NSEvent *)theEvent {
  // Toggle the path locking.

  BOOL  wasLocked = [pathModel isVisibleItemPathLocked];
  if (wasLocked) {
    // Unlock first, then build new path.
    [pathModel setVisibleItemPathLocking: NO];
  }

  NSPoint  loc = [theEvent locationInWindow];
  [self buildPathToMouseLoc: [self convertPoint: loc fromView: nil]];

  if (!wasLocked) {
    // Now lock, after having updated path.
    [pathModel setVisibleItemPathLocking: YES];
  }
}


- (void) mouseMoved: (NSEvent *)theEvent {
  if ([pathModel isVisibleItemPathLocked]) {
    // Ignore mouseMoved events the the item path is locked.
    //
    // Note: Although this view stops accepting mouse moved events when the
    // path becomes locked, these may be generated later on anyway, requested
    // by other components. In particular, mousing over the NSTextViews in the
    // drawer triggers mouse moved events again.
    return;
  }

  NSPoint  loc = [[self window] mouseLocationOutsideOfEventStream];
  // Note: not using the location returned by [theEvent locationInWindow] as
  // this is incorrect after the drawer has been clicked on.

  NSPoint  mouseLoc = [self convertPoint: loc fromView: nil];
  BOOL isInside = [self mouse: mouseLoc inRect: [self bounds]];

  if (isInside) {
    [self buildPathToMouseLoc: mouseLoc];
  }
  else {
    [pathModel clearVisibleItemPath];
  }
}

@end // @implementation DirectoryView


@implementation DirectoryView (PrivateMethods)

- (void) setItemPathModel:(ItemPathModel*)pathModelVal {
  NSAssert(pathModel==nil, @"The item path model should only be set once.");

  pathModel = [pathModelVal retain];

  [[NSNotificationCenter defaultCenter]
      addObserver: self selector: @selector(selectedItemChanged:)
      name: @"selectedItemChanged" object: pathModel];
  [[NSNotificationCenter defaultCenter]
      addObserver: self selector: @selector(visibleItemTreeChanged:)
      name: @"visibleItemTreeChanged" object: pathModel];
  [[NSNotificationCenter defaultCenter]
      addObserver: self selector: @selector(visibleItemPathLockingChanged:)
      name: @"visibleItemPathLockingChanged" object: pathModel];
          
  pathBuilder = [[ItemPathBuilder alloc] initWithPathModel: pathModel];

  [[NSNotificationCenter defaultCenter]
    addObserver: self selector: @selector(windowMainStatusChanged:)
    name: NSWindowDidBecomeMainNotification object: [self window]];
  [[NSNotificationCenter defaultCenter]
    addObserver: self selector: @selector(windowMainStatusChanged:)
    name: NSWindowDidResignMainNotification object: [self window]];
  
  [self visibleItemPathLockingChanged: nil];
  [self setNeedsDisplay: YES];
}


- (void) forceRedraw {
  [self setNeedsDisplay: YES];

  // Discard the existing image.
  [treeImage release];
  treeImage = nil;
}


- (void) itemTreeImageReady: (id) image {
  // Note: This method is called from the main thread (even though it has been
  // triggered by the drawer's background thread). So calling setNeedsDisplay
  // directly is okay.
  [treeImage release];
  treeImage = [image retain];
  
  [self setNeedsDisplay: YES];  
}


- (void) selectedItemChanged: (NSNotification *)notification {
  [self setNeedsDisplay: YES];
}

- (void) visibleItemTreeChanged: (NSNotification *)notification {
  // Discard the existing image.
  [treeImage release];
  treeImage = nil;
  
  [self setNeedsDisplay: YES];
}

- (void) visibleItemPathLockingChanged: (NSNotification *)notification {
  BOOL  locked = [pathModel isVisibleItemPathLocked];
  
  // Update the item path drawer directly. Although the drawer could also
  // listen to the notification, it seems better to do it like this. It keeps
  // the item path drawer more general, and as the item path drawer is tightly
  // integrated with this view, there is no harm in updating it directly.
  [pathDrawer setHighlightPathEndPoint: locked];
 
  [[self window] setAcceptsMouseMovedEvents: 
                   !locked && [[self window] isMainWindow]];
  
  [self setNeedsDisplay: YES];
}

- (void) windowMainStatusChanged: (NSNotification *)notification {
  [[self window] setAcceptsMouseMovedEvents: 
                   ![pathModel isVisibleItemPathLocked] && 
                   [[self window] isMainWindow]];
}


- (void) buildPathToMouseLoc: (NSPoint) point {
  [pathBuilder buildVisibleItemPathToPoint: point
                       usingLayoutBuilder: layoutBuilder
                       bounds: [self bounds]];
}

@end // @implementation DirectoryView (PrivateMethods)
