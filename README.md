# waveIMG
workflow for identifying breaking waves in surfzone video/imagery


## To Do:
create a new matlab-app for training data:
   1) get list of video-files (*i.e.*, path & filename; was `import_rod13.m`):
      - [x] prompt user to highlight directories where the vidoe files are located
      - [x] current directory drop-down selector for multiple video sub-directories
      - [ ] need call-back to update filenames when user selects a different sub-dir; anything else? 
      - [x] current filename drop-down selector for multiple videos in each sub-directory
      - [ ] \(do this later) will likely need call-backs to re-initialize video loading and rectification.
   2) load and rectify image frames from the selected movie (.avi or .mp4; was `rectify_vd.m`):
      - [ ] extract relevant variables/values from `getCameraParams.m` and `getOCMparams.m`
      - [ ] \(do this later) add an option for user to point to manually input values, direct to a .mat file with values.
      - [ ] read in a video frame
      - [ ] rectify the frame to user defined (x,y) grid,
            - editable fields for min/max of (x,y), and spacing (dx,dy)
	    - make default values the same as those used in `rectify_vd.m`
      - [ ] display frames
            - define axes properties,
	    - display using imagesc(x,y,frame)
	    - use a for-loop to show several frames (maybe 10) and make it like a movie using the `pause.m` command
            - stop on final image and prompt user to select breaking regions
   3) select points bounding the breaking wave fronts
      - [ ] use function like `drawfreehand.m` to select points using mouse
      - [ ] use these points to create a training label image where:
            - the size [rows,columns]=[ny,nx] of the label matches the rectified image
	    - the label is class uint8() and has values:
	      - 0 in the black bordering region outside the actual image
	      - 127 for non-breaking wave regions (beach, water, or trailing foam)
	      - 255 for points/regions selected by user
   4) archive training image/label pairs
      - [ ] use image origin directory and filename to create a training image/label filename
      - [ ] \(may do this sooner) resize the images to [512x255]; *e.g.*,
      ```
      trainingFrame = imresize( frame(:,:,t) , [512 255]);
      ```
		- make sure you also resize (x,y)
	    	- make sure the class is uint8
      - [ ] generate false color RGB training image by concatenating together three trainingImages;
      ```
      trainingImage = cat(3,traningFrame(:,:,t-dt),traningFrame(:,:,t),traningFrame(:,:,t+dt))
      ```
      - [ ] the images should be in a subdirectory called `trainingImages/`; labels should be in `trainingLabels/`
      - [ ] also keep a running log of the input image path, the frame number, and pixels used to make training labels

## Train the network and sell to google!

