#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

@interface SBIcon : NSObject
- (id)leafIdentifier;
@end

@interface SBIconImageView : UIView
@property (nonatomic, readonly) double continuousCornerRadius; 
- (UIImage *)squareContentsImage;
- (UIImage *)_currentOverlayImage;
@end

@interface SBLiveIconImageView : SBIconImageView
- (void)updateImageAnimated:(BOOL)arg1;
- (void)setIcon:(id)arg1 location:(long long)arg2 animated:(BOOL)arg3;
- (void)updateUnanimated;
- (void)updateAnimatingState;
- (BOOL)isAnimationAllowed;
- (void)prepareForReuse;
- (id)snapshot;
- (void)setPaused:(BOOL)arg1;
@end

@interface SBSafariIconImageView : SBLiveIconImageView
@property (nonatomic, retain) UIImageView *needle;
@property (nonatomic, retain) NSNumber *ls_pausedState;
- (void)ls_applyHeading:(CLLocationDegrees)heading;
@end
