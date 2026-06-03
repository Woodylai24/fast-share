interface FileInputProps {
  isDragging: boolean;
  onDrop: (e: React.DragEvent<HTMLDivElement>) => void;
  onDragOver: (e: React.DragEvent<HTMLDivElement>) => void;
  onDragEnter: (e: React.DragEvent<HTMLDivElement>) => void;
  onDragLeave: (e: React.DragEvent<HTMLDivElement>) => void;
  onBrowseFiles: () => void;
}

export function FileInput({
  onBrowseFiles,
}: FileInputProps) {
  return (
    <>
      <p style={{ color: "#aaa" }}>Drag & Drop files here to share</p>
      <button
        onClick={onBrowseFiles}
        style={{ marginBottom: "1rem" }}
      >
        Browse Files
      </button>
    </>
  );
}
