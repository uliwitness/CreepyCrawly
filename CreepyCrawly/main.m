//
//  main.m
//  CreepyCrawly
//
//  Created by Uli Kusterer on 03/04/16.
//  Copyright © 2016 Uli Kusterer. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface CCCrawler : NSObject

@property (strong) NSOperationQueue	*	crawlerQueue;
@property (strong) NSMutableArray *		visitedURLs;
@property (assign) NSInteger			maxDepth;

-(void)	startFromURLString: (NSString*)theURLString;	// Creates the queue and enqueues the first page (specified by theURLString) on it as a block that calls processOneURLString:.

-(void)	processOneURLString: (NSString*)theURLString depth: (NSInteger)currentDepth;	// Scans an individual page for links and calls -process:fromURLString: on it, then enqueues more calls of processOneURLString: on the crawlerQueue.

@end


@implementation CCCrawler

-(void)	startFromURLString:(NSString *)theURLString
{
	self.visitedURLs = [NSMutableArray array];
	self.crawlerQueue = [NSOperationQueue new];
	self.crawlerQueue.qualityOfService = NSQualityOfServiceUserInitiated;
	
	[self.crawlerQueue addOperationWithBlock: ^{
		[self processOneURLString: theURLString depth: 0];
	}];
}


-(void)	processOneURLString: (NSString*)theURLString depth: (NSInteger)currentDepth
{
	@synchronized(self)
	{
		if( [self.visitedURLs containsObject: theURLString] )
		{
			NSLog(@"DUPLICATE: %@", theURLString);
			return;	// Prevent ourselves from running around in circles.
		}
		[self.visitedURLs addObject: theURLString];
	}
	
	if( [theURLString hasPrefix: @"feed://"] )
		theURLString = [@"http" stringByAppendingString: [theURLString substringFromIndex: 4]];

	NSURL*	theURL = [NSURL URLWithString: theURLString];
	if( !theURL )
	{
		NSLog(@"ERROR[%@]: Invalid URL.", theURLString);
		return;
	}
	
	if( ![theURL.scheme isEqualToString: @"http"] && ![theURL.scheme isEqualToString: @"https"] )
	{
		NSLog(@"ERROR[%@]: Invalid Scheme.", theURLString);
		return;
	}
	
	NSLog(@"SCAN: %@", theURLString);
	
	NSURLSessionDataTask	*	theTask = [[NSURLSession sharedSession] dataTaskWithURL: theURL completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		@autoreleasepool
		{
			if( error )
			{
				NSLog(@"ERROR[%@]: %@", theURLString, error);
				return;
			}
			
			NSLog(@"FETCHED: %@", theURLString);
			
			NSHTTPURLResponse*	httpResponse = (NSHTTPURLResponse*)response;
			// +++ Should really check the page's encoding header and then pick the right one:
			NSString*	pageString = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
			if( !pageString )
			{
				NSLog(@"WARNING[%@]: Falling back on ISO Latin. (Actual: %@)", theURLString, httpResponse.allHeaderFields[@"Content-Encoding"]);
				pageString = [[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding];
			}
			
			NSString*	contentType = httpResponse.allHeaderFields[@"Content-Type"];
			if( [contentType containsString: @"text/html"] )
				[self process: pageString fromURLString: theURLString depth: currentDepth];
			else
				NSLog(@"TYPE[%@]: Ignoring content type %@", theURLString, contentType);
		}
	}];
	[theTask resume];
}


-(void)	process: (NSString*)pageString fromURLString: (NSString*)theURLString depth: (NSInteger)currentDepth
{
	if( currentDepth == self.maxDepth && currentDepth != 0 )
		return;
	
	NSError				*	error = nil;
	NSRegularExpression	*	regex = [NSRegularExpression regularExpressionWithPattern: @"<a\\s+(?:[^>]*?\\s+)?href=\"([^\"]*)\"" options: NSRegularExpressionCaseInsensitive error: &error];
	if( !regex )
	{
		NSLog(@"ERROR[%@]: Setting up Regex: %@", theURLString, error);
		return;
	}
	
	[regex enumerateMatchesInString: pageString options: 0 range: NSMakeRange(0,pageString.length) usingBlock: ^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop)
		{
			if( !result )
				return;
			NSString*	foundURL = [pageString substringWithRange: [result rangeAtIndex: 1]];
			NSLog(@"FOUND[%@]: %@", theURLString, foundURL);
			
			if( ![foundURL hasPrefix: @"http://"] && ![foundURL hasPrefix: @"https://"]
				&& ![foundURL hasPrefix: @"feed://"] )
			{
				NSLog(@"IGNORE[%@]: Ignoring URL due to scheme: %@", theURLString, foundURL);
				return;
			}

			[self.crawlerQueue addOperationWithBlock: ^{
				[self processOneURLString: foundURL depth: currentDepth +1];
			}];
		}];
}

@end


int main(int argc, const char * argv[]) {
	@autoreleasepool {
	    NSString			*	startURLString = [NSString stringWithUTF8String: argv[1]];
		
		NSLog(@"Launched with URL: %@", startURLString);
		
		CCCrawler			*	crawler = [CCCrawler new];
		crawler.maxDepth = 2;
		[crawler startFromURLString: startURLString];
		
		NSLog(@"Starting runloop.");
		
		NSRunLoop	*	runloop = [NSRunLoop currentRunLoop];
		[runloop run];
		
		NSLog(@"Returning from runloop (should never happen?)");
	}
    return 0;
}
