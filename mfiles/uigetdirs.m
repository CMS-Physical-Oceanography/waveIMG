function [pathname] = uigetdirs(path_in, dialog)
% Pick multiple files or directories using Java widgets
% by Andrew Janke 2011
import javax.swing.JFileChooser;

if nargin == 0 || isempty(path_in) == '' || path_in == 0 % Allow a null argument.
    path_in = pwd;
end

jchooser = javaObjectEDT('javax.swing.JFileChooser', path_in);

jchooser.setFileSelectionMode(JFileChooser.FILES_AND_DIRECTORIES);
if nargin > 1
    jchooser.setDialogTitle(dialog);
end

jchooser.setMultiSelectionEnabled(true);

status = jchooser.showOpenDialog([]);

if status == JFileChooser.APPROVE_OPTION
    jFile = jchooser.getSelectedFiles();
    pathname{size(jFile, 1)}=[];
    for i=1:size(jFile, 1)
        pathname{i} = char(jFile(i).getAbsolutePath);
    end

elseif status == JFileChooser.CANCEL_OPTION
    pathname = [];
else
    error('Error occured while picking file.');
end
end

