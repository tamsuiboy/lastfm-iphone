/* PlaybackViewController.m - Display currently-playing song info
 * 
 * Copyright 2011 Last.fm Ltd.
 *   - Primarily authored by Sam Steele <sam@last.fm>
 *
 * This file is part of MobileLastFM.
 *
 * MobileLastFM is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * MobileLastFM is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with MobileLastFM.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <MediaPlayer/MediaPlayer.h>
#import "PlaybackViewController.h"
#import "MobileLastFMApplicationDelegate.h"
#import "ProfileViewController.h"
#import "NowPlayingInfoViewController.h"
#import "UITableViewCell+ProgressIndicator.h"
#include "version.h"
#import "NSString+URLEscaped.h"
#import "UIViewController+NowPlayingButton.h"
#import "UIApplication+openURLWithWarning.h"
#import "NSString+MD5.h"
#if !(TARGET_IPHONE_SIMULATOR)
#import "FlurryAPI.h"
#endif

int tagSort(id tag1, id tag2, void *context) {
	if([[tag1 objectForKey:@"count"] intValue] < [[tag2 objectForKey:@"count"] intValue])
		return NSOrderedDescending;
	else if([[tag1 objectForKey:@"count"] intValue] > [[tag2 objectForKey:@"count"] intValue])
		return NSOrderedAscending;
	else
		return NSOrderedSame;
}

@implementation PlaybackViewController
@synthesize loveBtn;

- (void)showLoadingView {
	_loadingView.alpha = 1;
}
- (void)hideLoadingView {
	[UIView beginAnimations:nil context:nil];
	[UIView setAnimationDuration:0.5];
	_loadingView.alpha = 0;
	[UIView commitAnimations];
}
- (BOOL)canBecomeFirstResponder {
	return YES;
}
- (void)viewDidLoad {
	[super viewDidLoad];

	UIImage *image = [UIImage imageNamed:@"radio_back.png"];
	UIButton *btn = [[UIButton alloc] initWithFrame: CGRectMake(0, 0, image.size.width, image.size.height)];
	[btn setBackgroundImage:image forState:UIControlStateNormal];
	btn.adjustsImageWhenHighlighted = YES;
	[btn addTarget:self action:@selector(backButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem *backBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView: btn];
	[btn release];
	self.navigationItem.leftBarButtonItem = backBarButtonItem;
	[backBarButtonItem release];
	
	UIView *titleContainer = [[UIView alloc] initWithFrame:CGRectMake(0,0,200,28)];
	_titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,200,28)];
	_titleLabel.font = [UIFont boldSystemFontOfSize:21];
	_titleLabel.textAlignment = UITextAlignmentCenter;
	_titleLabel.backgroundColor = [UIColor clearColor];
	_titleLabel.textColor = [UIColor whiteColor];
	_titleLabel.adjustsFontSizeToFitWidth = YES;
	[titleContainer addSubview:_titleLabel];
	self.navigationItem.titleView = titleContainer;
	[titleContainer release];
	
	CGRect frame = volumeView.frame;
	frame.origin.y += 6;
	frame.size.height += 10;
	
#if !(TARGET_IPHONE_SIMULATOR)
	MPVolumeView *v = [[MPVolumeView alloc] initWithFrame:frame];
	[self.view insertSubview: v aboveSubview: volumeView];
	[volumeView removeFromSuperview];
	[volumeView release];
	volumeView = v;
	[volumeView sizeToFit];
	[v release];
#endif
	_lock = [[NSLock alloc] init];
	_reflectedArtworkView.transform = CGAffineTransformMake(1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f);
	_noArtworkView = [[UIImageView alloc] initWithFrame:_artworkView.bounds];
	_noArtworkView.image = [UIImage imageNamed:@"noartplaceholder.png"];
	_noArtworkView.opaque = NO;
	[_artworkView addSubview: _noArtworkView];
}
- (void)viewDidUnload {
	NSLog(@"Playback view unloaded");
	[super viewDidUnload];
	[_titleLabel release];
	_titleLabel = nil;
	[_lock release];
	_lock = nil;
	[_artworkURL release];
	_artworkURL = nil;
}
- (void)_systemVolumeChanged:(NSNotification *)notification {
	float volume = [[[notification userInfo] objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"] floatValue];
	for(UIView *v in [volumeView subviews]) {
		if([v isKindOfClass:[UISlider class]]) {
			if(((UISlider *)v).value != volume)
				((UISlider *)v).value = volume;
		}
	}
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	_titleLabel.text = [[[LastFMRadio sharedInstance] station] capitalizedString];
	[self becomeActive];
	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:YES];
	[self.navigationController.navigationBar setBarStyle:UIBarStyleBlack];
	[self.navigationController setToolbarHidden:YES];
}
- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self resignActive];
	[[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
	[self.navigationController.navigationBar setBarStyle:UIBarStyleDefault];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
- (void)backButtonPressed:(id)sender {
	[(MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate hidePlaybackView];
}
-(void)onTourButtonPressed:(id)sender {
	ArtistViewController *artist = [[ArtistViewController alloc] initWithArtist:[[[LastFMRadio sharedInstance] trackInfo] objectForKey:@"creator"]];
	[artist paintItBlack];
	[self.navigationController pushViewController:artist animated:YES];
	[artist release];
#if !(TARGET_IPHONE_SIMULATOR)
	[FlurryAPI logEvent:@"on-tour-strap"];
#endif
}
-(void)loveButtonPressed:(id)sender {
	[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate) loveButtonPressed:sender];	
}
-(void)banButtonPressed:(id)sender {
	[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate) banButtonPressed:sender];	
}
-(void)pauseButtonPressed:(id)sender {
	[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate) pauseButtonPressed:sender];	
}
-(void)skipButtonPressed:(id)sender {
	[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate) skipButtonPressed:sender];	
}
-(void)infoButtonPressed:(id)sender {
#if !(TARGET_IPHONE_SIMULATOR)
	[FlurryAPI logEvent:@"details"];
#endif
	NowPlayingInfoViewController *info = [[NowPlayingInfoViewController alloc] initWithTrackInfo:[[LastFMRadio sharedInstance] trackInfo]];
	[self.navigationController pushViewController:info animated:YES];
	[info release];
}
- (void)dealloc {
	[super dealloc];
	[_lock release];
	[_titleLabel release];
	[_artworkURL release];
}
- (void)becomeActive {
	if(!(_timer && [_timer isValid])) {
		NSLog(@"Resuming timer and subscribing to track changes");
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_trackDidChange:) name:kTrackDidChange object:nil];
		_timer = [NSTimer scheduledTimerWithTimeInterval:0.5
																							target:self
																						selector:@selector(_updateProgress:)
																						userInfo:nil
																						 repeats:YES];
		[self _displayTrackInfo:[[LastFMRadio sharedInstance] trackInfo]];
	}
}
- (void)resignActive {
	NSLog(@"Stopping timer and ignoring track changes");
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kTrackDidChange object:nil];
	[_timer invalidate];
	_timer = nil;
}
- (NSString *)formatTime:(int)seconds {
	if(seconds <= 0)
		return @"00:00";
	int h = seconds / 3600;
	int m = (seconds%3600) / 60;
	int s = seconds%60;
	if(h)
		return [NSString stringWithFormat:@"%02i:%02i:%02i", h, m, s];
	else
		return [NSString stringWithFormat:@"%02i:%02i", m, s];
}
- (void)_updateProgress:(NSTimer *)timer {
	if(!_timer) {
		[timer invalidate];
		return;
	}
	if([[LastFMRadio sharedInstance] state] != RADIO_IDLE) {
		float duration = [[[[LastFMRadio sharedInstance] trackInfo] objectForKey:@"duration"] floatValue]/1000.0f;
		float elapsed = [[LastFMRadio sharedInstance] trackPosition];
		
		_progress.progress = elapsed / duration;
		_elapsed.text = [self formatTime:elapsed];
		_remaining.text = [NSString stringWithFormat:@"-%@",[self formatTime:duration-elapsed]];
		_bufferPercentage.text = [NSString stringWithFormat:@"%i%%", (int)([[LastFMRadio sharedInstance] bufferProgress] * 100.0f)];
		if([LastFMRadio sharedInstance].state == TRACK_PAUSED)
			[stopBtn setImage:[UIImage imageNamed:@"controlbar_play.png"] forState:UIControlStateNormal];
		else
			[stopBtn setImage:[UIImage imageNamed:@"controlbar_pause.png"] forState:UIControlStateNormal];
	} else {
		[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate) hidePlaybackView];
		[_timer invalidate];
		_timer = nil;
		return;
	}
	if(([[LastFMRadio sharedInstance] state] == TRACK_BUFFERING || [[LastFMRadio sharedInstance] state] == RADIO_TUNING) && _loadingView.alpha < 1) {
		_loadingView.alpha = 1;
		loveBtn.alpha = 0.5;
		banBtn.alpha = 0.5;
		infoBtn.alpha = 0.5;
		stopBtn.alpha = 0.5;
		skipBtn.alpha = 0.5;
		if(self.navigationItem.rightBarButtonItem != nil)
			self.navigationItem.rightBarButtonItem.enabled = NO;
#if !(TARGET_IPHONE_SIMULATOR)
		[FlurryAPI logEvent:@"buffering" timed:YES];
#endif
	}
	if([[LastFMRadio sharedInstance] state] == TRACK_BUFFERING && _loadingView.alpha == 1 && _bufferPercentage.alpha < 1) {
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationDuration:10];
		_bufferPercentage.alpha = 1;
		[UIView commitAnimations];
	}
	if(([[LastFMRadio sharedInstance] state] != TRACK_BUFFERING && [[LastFMRadio sharedInstance] state] != RADIO_TUNING) && _loadingView.alpha == 1) {
		_bufferPercentage.alpha = 0;
		[UIView beginAnimations:nil context:nil];
		[UIView setAnimationDuration:0.5];
		_loadingView.alpha = 0;
		loveBtn.alpha = 1;
		banBtn.alpha = 1;
		infoBtn.alpha = 1;
		stopBtn.alpha = 1;
		skipBtn.alpha = 1;
		if(self.navigationItem.rightBarButtonItem != nil)
			self.navigationItem.rightBarButtonItem.enabled = YES;
		[UIView commitAnimations];
#if !(TARGET_IPHONE_SIMULATOR)
		[FlurryAPI endTimedEvent:@"buffering" withParameters:nil];
#endif
	}
}
- (void)_fetchArtwork:(NSDictionary *)trackInfo {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[trackInfo retain];
	[_lock lock];
	NSDictionary *albumData = [[LastFMService sharedInstance] metadataForAlbum:[trackInfo objectForKey:@"album"] byArtist:[trackInfo objectForKey:@"creator"] inLanguage:[[[NSUserDefaults standardUserDefaults] objectForKey: @"AppleLanguages"] objectAtIndex:0]];
	NSString *artworkURL = nil;
	UIImage *artworkImage;
	
	if([[albumData objectForKey:@"image"] length]) {
		artworkURL = [NSString stringWithString:[albumData objectForKey:@"image"]];
	} else if([[trackInfo objectForKey:@"image"] length]) {
		artworkURL = [NSString stringWithString:[trackInfo objectForKey:@"image"]];
	}
	
	if(!artworkURL || [artworkURL isEqualToString:@"http://cdn.last.fm/depth/catalogue/noimage/cover_med.gif"] || [artworkURL isEqualToString:@"http://cdn.last.fm/depth/catalogue/noimage/cover_large.gif"]) {
		NSDictionary *artistData = [[LastFMService sharedInstance] metadataForArtist:[trackInfo objectForKey:@"creator"] inLanguage:[[[NSUserDefaults standardUserDefaults] objectForKey: @"AppleLanguages"] objectAtIndex:0]];
		if([artistData objectForKey:@"image"])
			artworkURL = [NSString stringWithString:[artistData objectForKey:@"image"]];
	}
	
	if(artworkURL && [artworkURL rangeOfString:@"amazon.com"].location != NSNotFound) {
		artworkURL = [artworkURL stringByReplacingOccurrencesOfString:@"MZZZ" withString:@"LZZZ"];
	}
	
	if(![artworkURL isEqualToString:_artworkURL]) {
		NSLog(@"Loading artwork: %@\n", artworkURL);
		[UIView beginAnimations:nil context:nil];
		[artwork release];
		artwork = [[UIImage imageNamed:@"noartplaceholder.png"] retain];
		_noArtworkView.alpha = 1;
		_reflectedArtworkView.image = artwork;
		[UIView commitAnimations];
		if(artworkURL && ![artworkURL isEqualToString:@"http://cdn.last.fm/depth/catalogue/noimage/cover_med.gif"] && ![artworkURL isEqualToString:@"http://cdn.last.fm/depth/catalogue/noimage/cover_large.gif"]) {
			NSData *imageData = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString: artworkURL]];
			artworkImage = [[UIImage alloc] initWithData:imageData];
			[imageData release];
		} else {
			artworkImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"noartplaceholder" ofType:@"png"]];
		}
		
		if([[trackInfo objectForKey:@"title"] isEqualToString:[[[LastFMRadio sharedInstance] trackInfo] objectForKey:@"title"]] &&
			 [[trackInfo objectForKey:@"creator"] isEqualToString:[[[LastFMRadio sharedInstance] trackInfo] objectForKey:@"creator"]]) {
			_artworkView.image = artworkImage;
			_reflectedArtworkView.image = artworkImage;
			[artwork release];
			artwork = artworkImage;
			[_artworkURL release];
			_artworkURL = [artworkURL retain];
			[UIView beginAnimations:nil context:nil];
			_noArtworkView.alpha = 0;
			[UIView commitAnimations];
		} else {
			[artworkImage release];
		}
	}
	[_lock unlock];
	[trackInfo release];
	[pool release];
}
- (void)_updateBadge:(NSDictionary *)trackInfo {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[trackInfo retain];
	
	if([[[NSUserDefaults standardUserDefaults] objectForKey:@"showontour"] isEqualToString:@"YES"]) {
		NSArray *events = [[LastFMService sharedInstance] eventsForArtist:[trackInfo objectForKey:@"creator"]];
		if([events count]) {
			if(_badge) {
				[UIView beginAnimations:nil context:nil];
				_badge.alpha = 1;
				[UIView commitAnimations];
			}
		} else {
			if(_badge) {
				[UIView beginAnimations:nil context:nil];
				_badge.alpha = 0;
				[UIView commitAnimations];
			}
		}
	}
	[trackInfo release];
	[pool release];
}	
- (void)_displayTrackInfo:(NSDictionary *)trackInfo {
	_artistAndTrackTitle.text = [NSString stringWithFormat:@"%@ – %@", [trackInfo objectForKey:@"creator"], [trackInfo objectForKey:@"title"]];
	_elapsed.text = @"0:00";
	_remaining.text = [NSString stringWithFormat:@"-%@",[self formatTime:([[trackInfo objectForKey:@"duration"] floatValue] / 1000.0f)]];
	_progress.progress = 0;
	if([LastFMRadio sharedInstance].state == TRACK_PAUSED)
		[stopBtn setImage:[UIImage imageNamed:@"controlbar_play.png"] forState:UIControlStateNormal];
	else
		[stopBtn setImage:[UIImage imageNamed:@"controlbar_pause.png"] forState:UIControlStateNormal];

	[UIView beginAnimations:nil context:nil];
	if([[trackInfo objectForKey:@"context"] count] > 0) {
		_fullscreenMetadataView.frame = CGRectMake(0,0,320,67);
		_context.alpha = 1;
		NSString *context = @"";
		if([[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/friends"] || [[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/neighbours"])
			context = @"From ";
		else
			context = @"Similar to ";
		NSArray *contextitems = [trackInfo objectForKey:@"context"];
		int contextitemscount = 0;
		for(int i = 1; i < [contextitems count] && i < 3; i++) {
			if([[[contextitems objectAtIndex:i] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) {
				contextitemscount++;
				if(i > 1)
					context = [context stringByAppendingString:@" and "];
				context = [context stringByAppendingString:[[contextitems objectAtIndex:i] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]]];
				if([[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/friends"] || [[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/neighbours"]) {
					if([context hasSuffix:@"s"])
						context = [context stringByAppendingString:@"’"];
					else
						context = [context stringByAppendingString:@"’s"];
				}
			}
		}
		if([[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/friends"] || [[[LastFMRadio sharedInstance] stationURL] hasSuffix:@"/neighbours"]) {
			if(contextitemscount > 1)
				context = [context stringByAppendingString:@" libraries"];
			else
				context = [context stringByAppendingString:@" library"];
		}
		_context.text = context;
	} else {
		_fullscreenMetadataView.frame = CGRectMake(0,0,320,52);
		_context.alpha = 0;
	}
	[UIView commitAnimations];
	[self _updateProgress:nil];
	if([[[LastFMRadio sharedInstance] stationURL] hasPrefix:@"lastfm://artist/"] || [[[LastFMRadio sharedInstance] stationURL] hasPrefix:@"lastfm://globaltags/"]) {
		self.navigationItem.rightBarButtonItem = nil;
	} else {
		UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(filterButtonPressed:)];
		if([LastFMRadio sharedInstance].state == TRACK_BUFFERING || [LastFMRadio sharedInstance].state == RADIO_TUNING)
			item.enabled = NO;
		self.navigationItem.rightBarButtonItem = item;
		[item release];
	}

	[UIView beginAnimations:nil context:nil];
	
	[[self.navigationItem.titleView subviews] makeObjectsPerformSelector:@selector(removeFromSuperview)];
	
	NSString *stationURL = [[LastFMRadio sharedInstance] stationURL];
	NSRange range = [[[LastFMRadio sharedInstance] stationURL] rangeOfString:@"/tag/"];
	if(range.location != NSNotFound) {
		NSString *tag = [[[[LastFMRadio sharedInstance] stationURL] substringFromIndex:range.location + 5] unURLEscape];
		stationURL = [[[LastFMRadio sharedInstance] stationURL] substringToIndex:range.location];
		_titleLabel.frame = CGRectMake(0,0,200,14);
		_titleLabel.font = [UIFont systemFontOfSize:12];
		[self.navigationItem.titleView addSubview: _titleLabel];
		UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(0,14,200,14)];
		subtitle.text = [NSString stringWithFormat:@"Playing just '%@'", tag];
		subtitle.font = [UIFont systemFontOfSize:12];
		subtitle.textColor = [UIColor grayColor];
		subtitle.backgroundColor = [UIColor clearColor];
		subtitle.textAlignment = UITextAlignmentCenter;
		[self.navigationItem.titleView addSubview: subtitle];
		[subtitle release];
	} else {
		_titleLabel.frame = CGRectMake(0,0,200,28);
		_titleLabel.font = [UIFont boldSystemFontOfSize:21];
		[self.navigationItem.titleView addSubview: _titleLabel];
	}
	
	range = [stationURL rangeOfString:@"/personal"];
	if(range.location != NSNotFound && [stationURL hasSuffix:@"/personal"]) {
		NSString *user = [[[stationURL substringFromIndex:14] substringToIndex:range.location - 14] unURLEscape];
		if([user isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"lastfm_user"]])
			_titleLabel.text = @"My Library Radio";
		else
			_titleLabel.text = [NSString stringWithFormat:@"%@’s Library Radio", user];
	}
	
	range = [stationURL rangeOfString:@"/mix"];
	if(range.location != NSNotFound && [stationURL hasSuffix:@"/mix"]) {
		NSString *user = [[[stationURL substringFromIndex:14] substringToIndex:range.location - 14] unURLEscape];
		if([user isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"lastfm_user"]])
			_titleLabel.text = @"My Mix Radio";
		else
			_titleLabel.text = [NSString stringWithFormat:@"%@’s Mix Radio", user];
	}
	
	range = [stationURL rangeOfString:@"/recommended"];
	if(range.location != NSNotFound && [stationURL hasSuffix:@"/recommended"]) {
		NSString *user = [[[stationURL substringFromIndex:14] substringToIndex:range.location - 14] unURLEscape];
		if([user isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"lastfm_user"]])
			_titleLabel.text = @"My Recommended Radio";
		else
			_titleLabel.text = [NSString stringWithFormat:@"%@’s Recommended Radio", user];
	}
	
	range = [stationURL rangeOfString:@"/friends"];
	if(range.location != NSNotFound && [stationURL hasSuffix:@"/friends"]) {
		NSString *user = [[[stationURL substringFromIndex:14] substringToIndex:range.location - 14] unURLEscape];
		if([user isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"lastfm_user"]])
			_titleLabel.text = @"Friends’ Radio";
		else
			_titleLabel.text = [NSString stringWithFormat:@"%@’s Friends’ Radio", user];
	}
	
	range = [stationURL rangeOfString:@"/neighbours"];
	if(range.location != NSNotFound && [stationURL hasSuffix:@"/neighbours"]) {
		NSString *user = [[[stationURL substringFromIndex:14] substringToIndex:range.location - 14] unURLEscape];
		if([user isEqualToString:[[NSUserDefaults standardUserDefaults] objectForKey:@"lastfm_user"]])
			_titleLabel.text = @"Neighbourhood Radio";
		else
			_titleLabel.text = [NSString stringWithFormat:@"%@’s Neighbourhood Radio", user];
	}
	
	_titleLabel.text = [_titleLabel.text capitalizedString];
	
	[UIView commitAnimations];
	
	[NSThread detachNewThreadSelector:@selector(_updateBadge:) toTarget:self withObject:trackInfo];
	[NSThread detachNewThreadSelector:@selector(_fetchArtwork:) toTarget:self withObject:trackInfo];
}
-(void)artworkButtonPressed:(id)sender {
	[UIView beginAnimations:nil context:nil];
	if(_fullscreenMetadataView.alpha == 1) {
		_fullscreenMetadataView.alpha = 0;
	} else {
		_fullscreenMetadataView.alpha = 1;
	}
	[UIView commitAnimations];
}
-(void)filterButtonPressed:(id)sender {
	[_filter reloadAllComponents];
	[UIView beginAnimations:nil context:nil];
	_filterView.frame = CGRectMake(0,156,320,260);
	[UIView commitAnimations];
}
-(void)_tuneNewStation:(NSDictionary *)filter {
	if(![[LastFMRadio sharedInstance] selectStation:[filter objectForKey:@"url"]]) {
		[(MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate reportError:[LastFMService sharedInstance].error];
	} else {
		if([filter objectForKey:@"name"]) {
#if !(TARGET_IPHONE_SIMULATOR)
			[FlurryAPI logEvent:@"filter"];
#endif
			UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Station Retuned" message:
														 [NSString stringWithFormat:@"After this track, you'll only hear '%@' music on this station.",[filter objectForKey:@"name"]]
																											delegate:[UIApplication sharedApplication].delegate cancelButtonTitle:NSLocalizedString(@"OK", @"OK") otherButtonTitles:nil] autorelease];
			[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:YES];
		} else {
#if !(TARGET_IPHONE_SIMULATOR)
			[FlurryAPI logEvent:@"unfilter"];
#endif
			UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Station Retuned" message:@"After this track, you'll hear all music on this station."
																											delegate:[UIApplication sharedApplication].delegate cancelButtonTitle:NSLocalizedString(@"OK", @"OK") otherButtonTitles:nil] autorelease];
			[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:YES];
		}
	}
}
-(void)dismissFilterView:(id)sender {
	[UIView beginAnimations:nil context:nil];
	_filterView.frame = CGRectMake(0,480,320,254);
	[UIView commitAnimations];
	if([_filter selectedRowInComponent:0] == 0) {
		NSRange range = [[[LastFMRadio sharedInstance] stationURL] rangeOfString:@"/tag/"];
		if(range.location != NSNotFound) {
			NSString *url = [[[LastFMRadio sharedInstance] stationURL] substringToIndex:range.location];
			NSLog(@"New URL: %@", url);
			[self performSelector:@selector(_tuneNewStation:) withObject:[NSDictionary dictionaryWithObjectsAndKeys:url,@"url",nil,nil] afterDelay:0.1];
		}
	} else if(![[[LastFMRadio sharedInstance] stationURL] isEqualToString:[[[[LastFMRadio sharedInstance] suggestions] objectAtIndex:[_filter selectedRowInComponent:0]-1] objectForKey:@"url"]]) {
		NSLog(@"New URL: %@", [[[[LastFMRadio sharedInstance] suggestions] objectAtIndex:[_filter selectedRowInComponent:0]-1] objectForKey:@"url"]);
		[self performSelector:@selector(_tuneNewStation:) withObject:[[[LastFMRadio sharedInstance] suggestions] objectAtIndex:[_filter selectedRowInComponent:0]-1] afterDelay:0.1];
	}
}
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)thePickerView {
	return 1;
}
- (NSInteger)pickerView:(UIPickerView *)thePickerView numberOfRowsInComponent:(NSInteger)component {
	return [[[LastFMRadio sharedInstance] suggestions] count] + 1;
}
- (NSString *)pickerView:(UIPickerView *)thePickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
	if(row == 0)
		return @"Include all tags";
	else
		return [[[[LastFMRadio sharedInstance] suggestions] objectAtIndex:(row-1)] objectForKey:@"name"];
}
- (void)_trackDidChange:(NSNotification *)notification {
	_titleLabel.text = [[[LastFMRadio sharedInstance] station] capitalizedString];
	if([[[[LastFMRadio sharedInstance] trackInfo] objectForKey:@"loved"] isEqualToString:@"1"])
		loveBtn.selected = YES;
	else
		loveBtn.selected = NO;
	[UIView beginAnimations:nil context:nil];
	[artwork release];
	artwork = [[UIImage imageNamed:@"noartplaceholder.png"] retain];
	_noArtworkView.alpha = 1;
	_reflectedArtworkView.image = artwork;
	_badge.alpha = 0;
	[UIView commitAnimations];
	NSDictionary *trackInfo = [notification userInfo];
	[self _displayTrackInfo:trackInfo];
	NSLog(@"Free trial tracks remaining: %@", [[NSUserDefaults standardUserDefaults] objectForKey:@"trial_playsleft"]);
}
@end
