//
//  MultiMatchStringTest.m
//  GrandPerspective
//
//  Created by Erwin on 26/05/2006.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "MultiMatchStringTest.h"


@interface MultiMatchStringTest (PrivateMethods) 

// Not implemented. Needs to be provided by subclass.
- (BOOL) testString:(NSString*)string matches:(NSString*)match;

// Not implemented. Needs to be provided by subclass.
- (NSString*) descriptionOfTest;

@end


@implementation MultiMatchStringTest

- (id) initWithMatches:(NSArray*)matchesVal {
  if (self = [super init]) {
    NSAssert([matchesVal count] >= 1, 
             @"There must at least be one possible match.");

    matches = [matchesVal retain];
  }
}

- (void) dealloc {
  [matches release];

  [super dealloc];
}


- (BOOL) testString:(NSString*)string {
  NSEnumerator*  matchEnum = [matches objectEnumerator];
  NSString*  match;
  while (match = [matchEnum nextObject]) {
    if ([self testString:string matches:match]) {
      return YES;
    }
  }
  
  return NO;
}

- (NSString*) descriptionWithSubject:(NSString*)subject {
  NSMutableString*  descr = [NSMutableString stringWithCapacity:128];
  
  [descr setString:subject];
  [descr appendString:@" "];
  [descr appendString:[self descriptionOfTest]];
  [descr appendString:@" "];
  
  NSEnumerator*  matchEnum = [matches objectEnumerator];

  // Can assume there is always one.
  [descr appendString:[matchEnum nextObject]];

  NSString*  match = [matchEnum nextObject];

  if (match) {
    NSString*  prevMatch = match;
  
    while (match = [matchEnum nextObject]) {
      [descr appendString:@", "];
      [descr appendString:prevMatch];
      prevMatch = match;
    }
    [descr appendString:@" or "];
    [descr appendString:prevMatch];
  }

  return descr;
}

@end
